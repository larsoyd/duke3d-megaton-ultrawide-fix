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

const (
	BackupName = "duke3d.megaton-original"
	GameFolder = "Duke Nukem 3D"
)

type Change struct {
	Offset, Old, New uint32
	Label            string
}

type Patch struct {
	OriginalSHA, PatchedSHA string
	Changes                 []Change
}

func refused(format string, args ...any) error {
	return fmt.Errorf("refused: "+format, args...)
}

func ParsePatch(manifest, changes string) (Patch, error) {
	var p Patch
	for _, line := range strings.Split(manifest, "\n") {
		k, v, ok := strings.Cut(line, "=")
		switch {
		case ok && k == "ORIGINAL_SHA256":
			p.OriginalSHA = v
		case ok && k == "PATCHED_SHA256":
			p.PatchedSHA = v
		}
	}
	if len(p.OriginalSHA) != 64 || len(p.PatchedSHA) != 64 {
		return p, refused("manifest has no checksums")
	}
	for n, line := range strings.Split(strings.TrimSpace(changes), "\n") {
		f := strings.Split(line, "\t")
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

func Embedded() (Patch, error) {
	return ParsePatch(ultrawide.Manifest, ultrawide.Changes)
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

func paths(game string) (exe, backup string, err error) {
	exe = filepath.Join(game, "bin", "duke3d")
	if _, err = os.Stat(exe); err != nil {
		return "", "", refused("game not found: no bin/duke3d in %s", game)
	}
	return exe, filepath.Join(game, "bin", BackupName), nil
}

func Status(p Patch, game string) (string, error) {
	exe, _, err := paths(game)
	if err != nil {
		return "", err
	}
	sum, err := fileSHA(exe)
	if err != nil {
		return "", err
	}
	switch sum {
	case p.OriginalSHA:
		return "original", nil
	case p.PatchedSHA:
		return "patched", nil
	}
	return "unknown", nil
}

func Install(p Patch, game string) (string, error) {
	exe, backup, err := paths(game)
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(exe)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	switch got := hex.EncodeToString(sum[:]); got {
	case p.PatchedSHA:
		return "already patched", nil
	case p.OriginalSHA:
	default:
		return "", refused("unknown executable sha256=%s, expected %s", got, p.OriginalSHA)
	}
	st, err := os.Stat(exe)
	if err != nil {
		return "", err
	}
	patched, err := p.apply(data)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(backup); err != nil {
		if err := writeBeside(backup, data, st.Mode().Perm()); err != nil {
			return "", err
		}
	}
	if s, _ := fileSHA(backup); s != p.OriginalSHA {
		return "", refused("backup %s is not the original", backup)
	}
	if err := writeBeside(exe, patched, st.Mode().Perm()); err != nil {
		return "", err
	}
	return "patched sha256=" + p.PatchedSHA, nil
}

func Uninstall(p Patch, game string) (string, error) {
	exe, backup, err := paths(game)
	if err != nil {
		return "", err
	}
	cur, err := fileSHA(exe)
	if err != nil {
		return "", err
	}
	switch cur {
	case p.OriginalSHA:
		return "not patched, nothing to restore", nil
	case p.PatchedSHA:
	default:
		return "", refused("unknown executable sha256=%s, leaving it alone", cur)
	}
	data, err := os.ReadFile(backup)
	if err != nil {
		return "", refused("backup %s is missing, use Steam to verify the game files", backup)
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != p.OriginalSHA {
		return "", refused("backup %s does not match the original", backup)
	}
	st, err := os.Stat(exe)
	if err != nil {
		return "", err
	}
	if err := writeBeside(exe, data, st.Mode().Perm()); err != nil {
		return "", err
	}
	if s, _ := fileSHA(exe); s != p.OriginalSHA {
		return "", refused("restore did not verify")
	}
	if err := os.Remove(backup); err != nil {
		return "", err
	}
	return "restored sha256=" + p.OriginalSHA, nil
}

var vdfPath = regexp.MustCompile(`^\s*"path"\s*"(.*)"\s*$`)

func Locate(home string) []string {
	var libs []string
	for _, root := range []string{".local/share/Steam", ".steam/steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam"} {
		root = filepath.Join(home, root)
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
		if _, err := os.Stat(filepath.Join(dir, "bin", "duke3d")); err != nil {
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

func ResolveGame(home, dir string) (string, error) {
	if dir != "" {
		if _, _, err := paths(dir); err != nil {
			return "", err
		}
		return filepath.Abs(dir)
	}
	found := Locate(home)
	switch len(found) {
	case 1:
		return found[0], nil
	case 0:
		return "", refused("game not found in any Steam library, pass --game-dir")
	}
	return "", refused("several installs found (%s), pass --game-dir", strings.Join(found, ", "))
}
