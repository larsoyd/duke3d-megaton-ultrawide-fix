package engine

import (
	"bufio"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	ultrawide "github.com/larsoyd/duke3d-megaton-ultrawide-fix"
)

const GameFolder = "Duke Nukem 3D"

type Change struct {
	Offset, Old, New uint32
	Label            string
}

type Patch struct {
	OriginalSHA, PatchedSHA string
	Exe, Backup             string
	Changes                 []Change
}

func refused(format string, args ...any) error {
	return fmt.Errorf("refused: "+format, args...)
}

func ParsePatch(manifest, changes string) (Patch, error) {
	var p Patch
	for _, line := range strings.Split(manifest, "\n") {
		k, v, ok := strings.Cut(strings.TrimRight(line, "\r"), "=")
		switch {
		case ok && k == "ORIGINAL_SHA256":
			p.OriginalSHA = v
		case ok && k == "PATCHED_SHA256":
			p.PatchedSHA = v
		case ok && k == "EXE":
			p.Exe = v
		case ok && k == "BACKUP":
			p.Backup = v
		}
	}
	if len(p.OriginalSHA) != 64 || len(p.PatchedSHA) != 64 {
		return p, refused("manifest has no checksums")
	}
	if p.Exe == "" || p.Backup == "" {
		return p, refused("manifest has no EXE or BACKUP")
	}
	for n, line := range strings.Split(strings.TrimSpace(changes), "\n") {
		f := strings.Split(strings.TrimRight(line, "\r"), "\t")
		if len(f) != 4 {
			return p, refused("change table line %d has %d fields", n+1, len(f))
		}
		var c Change
		for i, dst := range []*uint32{&c.Offset, &c.Old, &c.New} {
			v, err := strconv.ParseUint(f[i], 0, 32)
			if err != nil {
				return p, refused("change table line %d: %v", n+1, err)
			}
			*dst = uint32(v)
		}
		c.Label = f[3]
		p.Changes = append(p.Changes, c)
	}
	return p, nil
}

func Embedded() ([]Patch, error) {
	var ps []Patch
	for _, dir := range ultrawide.PatchDirs {
		m, err := ultrawide.Patches.ReadFile(dir + "/manifest")
		if err != nil {
			return nil, err
		}
		c, err := ultrawide.Patches.ReadFile(dir + "/changes.tsv")
		if err != nil {
			return nil, err
		}
		p, err := ParsePatch(string(m), string(c))
		if err != nil {
			return nil, err
		}
		ps = append(ps, p)
	}
	return ps, nil
}

func fileSHA(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func (p Patch) apply(data []byte) ([]byte, error) {
	out := append([]byte(nil), data...)
	for _, c := range p.Changes {
		if int(c.Offset)+4 > len(out) {
			return nil, refused("offset 0x%08x %s is past the end of the file", c.Offset, c.Label)
		}
		if have := binary.LittleEndian.Uint32(out[c.Offset:]); have != c.Old {
			return nil, refused("offset 0x%08x %s holds 0x%08x, expected 0x%08x", c.Offset, c.Label, have, c.Old)
		}
		binary.LittleEndian.PutUint32(out[c.Offset:], c.New)
	}
	sum := sha256.Sum256(out)
	if got := hex.EncodeToString(sum[:]); got != p.PatchedSHA {
		return nil, refused("patched checksum %s does not match %s", got, p.PatchedSHA)
	}
	return out, nil
}

func writeBeside(dest string, data []byte, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(dest), ".duke3d.")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), dest)
}

type target struct {
	Patch
	exe, backup string
	data        []byte
	state       string
}

// load reads every known exe in the folder and refuses before any write if one is unknown.
func load(ps []Patch, game string) ([]target, error) {
	var ts []target
	for _, p := range ps {
		exe := filepath.Join(game, filepath.FromSlash(p.Exe))
		data, err := os.ReadFile(exe)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return nil, err
		}
		t := target{Patch: p, exe: exe, backup: filepath.Join(filepath.Dir(exe), p.Backup), data: data}
		sum := sha256.Sum256(data)
		switch got := hex.EncodeToString(sum[:]); got {
		case p.OriginalSHA:
			t.state = "original"
		case p.PatchedSHA:
			t.state = "patched"
		default:
			return nil, refused("unknown executable %s sha256=%s, expected %s", p.Exe, got, p.OriginalSHA)
		}
		ts = append(ts, t)
	}
	if len(ts) == 0 {
		return nil, refused("game not found: no %s in %s", exeNames(ps), game)
	}
	return ts, nil
}

func exeNames(ps []Patch) string {
	var n []string
	for _, p := range ps {
		n = append(n, p.Exe)
	}
	return strings.Join(n, " or ")
}

func hasGame(ps []Patch, dir string) bool {
	for _, p := range ps {
		if _, err := os.Stat(filepath.Join(dir, filepath.FromSlash(p.Exe))); err == nil {
			return true
		}
	}
	return false
}

func each(ps []Patch, game string, fn func(target) (string, error)) (string, error) {
	ts, err := load(ps, game)
	if err != nil {
		return "", err
	}
	var msgs []string
	for _, t := range ts {
		msg, err := fn(t)
		if err != nil {
			return "", err
		}
		msgs = append(msgs, t.Exe+"="+msg)
	}
	return strings.Join(msgs, " "), nil
}

func Status(ps []Patch, game string) (string, error) {
	return each(ps, game, func(t target) (string, error) { return t.state, nil })
}

func Install(ps []Patch, game string) (string, error) {
	return each(ps, game, install)
}

func install(t target) (string, error) {
	if t.state == "patched" {
		return "already patched", nil
	}
	st, err := os.Stat(t.exe)
	if err != nil {
		return "", err
	}
	patched, err := t.apply(t.data)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(t.backup); err != nil {
		if err := writeBeside(t.backup, t.data, st.Mode().Perm()); err != nil {
			return "", err
		}
	}
	if s, _ := fileSHA(t.backup); s != t.OriginalSHA {
		return "", refused("backup %s is not the original", t.backup)
	}
	if err := writeBeside(t.exe, patched, st.Mode().Perm()); err != nil {
		return "", err
	}
	return "patched sha256=" + t.PatchedSHA, nil
}

func Uninstall(ps []Patch, game string) (string, error) {
	return each(ps, game, uninstall)
}

func uninstall(t target) (string, error) {
	if t.state == "original" {
		return "not patched, nothing to restore", nil
	}
	data, err := os.ReadFile(t.backup)
	if err != nil {
		return "", refused("backup %s is missing, use Steam to verify the game files", t.backup)
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != t.OriginalSHA {
		return "", refused("backup %s does not match the original", t.backup)
	}
	st, err := os.Stat(t.exe)
	if err != nil {
		return "", err
	}
	if err := writeBeside(t.exe, data, st.Mode().Perm()); err != nil {
		return "", err
	}
	if s, _ := fileSHA(t.exe); s != t.OriginalSHA {
		return "", refused("restore did not verify")
	}
	if err := os.Remove(t.backup); err != nil {
		return "", err
	}
	return "restored sha256=" + t.OriginalSHA, nil
}

var vdfPath = regexp.MustCompile(`^\s*"path"\s*"(.*)"\s*$`)

func steamRoots(home string) []string {
	var roots []string
	for _, r := range []string{".local/share/Steam", ".steam/steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam"} {
		roots = append(roots, filepath.Join(home, r))
	}
	if pf := os.Getenv("ProgramFiles(x86)"); pf != "" {
		roots = append(roots, filepath.Join(pf, "Steam"))
	}
	return roots
}

func Locate(ps []Patch, home string) []string {
	var libs []string
	for _, root := range steamRoots(home) {
		if _, err := os.Stat(filepath.Join(root, "steamapps")); err != nil {
			continue
		}
		libs = append(libs, root)
		f, err := os.Open(filepath.Join(root, "steamapps", "libraryfolders.vdf"))
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			if m := vdfPath.FindStringSubmatch(sc.Text()); m != nil {
				libs = append(libs, strings.ReplaceAll(m[1], `\\`, `\`))
			}
		}
		f.Close()
	}
	seen := map[string]bool{}
	var found []string
	for _, lib := range libs {
		dir := filepath.Join(lib, "steamapps", "common", GameFolder)
		if !hasGame(ps, dir) {
			continue
		}
		if real, err := filepath.EvalSymlinks(dir); err == nil {
			dir = real
		}
		if !seen[dir] {
			seen[dir] = true
			found = append(found, dir)
		}
	}
	sort.Strings(found)
	return found
}

func ResolveGame(ps []Patch, home, dir string) (string, error) {
	if dir != "" {
		if !hasGame(ps, dir) {
			return "", refused("game not found: no %s in %s", exeNames(ps), dir)
		}
		return filepath.Abs(dir)
	}
	found := Locate(ps, home)
	switch len(found) {
	case 1:
		return found[0], nil
	case 0:
		return "", refused("game not found in any Steam library, pass --game-dir")
	}
	return "", refused("several installs found (%s), pass --game-dir", strings.Join(found, ", "))
}
