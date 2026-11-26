package engine

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

type fakeExe struct {
	exe, backup       string
	original, patched []byte
	patch             Patch
}

type fixture struct {
	game, home string
	lin, win   fakeExe
}

func shaHex(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func newTarget(t *testing.T, exe, backup string) fakeExe {
	t.Helper()
	tg := fakeExe{exe: exe, backup: backup, original: make([]byte, 4096)}
	if _, err := rand.Read(tg.original); err != nil {
		t.Fatal(err)
	}
	binary.LittleEndian.PutUint32(tg.original[100:], 0x093C28E0)
	binary.LittleEndian.PutUint32(tg.original[200:], 0xA00)
	tg.patched = append([]byte(nil), tg.original...)
	binary.LittleEndian.PutUint32(tg.patched[100:], 0x098AA1C0)
	binary.LittleEndian.PutUint32(tg.patched[200:], 0x2000)
	manifest := fmt.Sprintf("ORIGINAL_SHA256=%s\nPATCHED_SHA256=%s\nEXE=%s\nBACKUP=%s\n",
		shaHex(tg.original), shaHex(tg.patched), exe, backup)
	changes := "0x00000064\t0x093c28e0\t0x098aa1c0\tumost+0\n0x000000c8\t0x00000a00\t0x00002000\twidth_clamp\n"
	p, err := ParsePatch(manifest, changes)
	if err != nil {
		t.Fatal(err)
	}
	tg.patch = p
	return tg
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	dir := t.TempDir()
	f := &fixture{game: filepath.Join(dir, "game"), home: filepath.Join(dir, "home")}
	f.lin = newTarget(t, "bin/duke3d", "duke3d.megaton-original")
	f.win = newTarget(t, "bin/duke3d.exe", "duke3d.exe.megaton-original")
	if err := os.MkdirAll(filepath.Join(f.game, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	f.write(t, f.lin.exe, f.lin.original, 0o751)
	return f
}

func (f *fixture) patches() []Patch { return []Patch{f.lin.patch, f.win.patch} }

func (f *fixture) sha(t *testing.T, rel string) string { return shaHex(f.read(t, rel)) }

func (f *fixture) write(t *testing.T, rel string, data []byte, mode os.FileMode) {
	t.Helper()
	p := filepath.Join(f.game, rel)
	if err := os.WriteFile(p, data, mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(p, mode); err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) read(t *testing.T, rel string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(f.game, rel))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func (f *fixture) leftovers(t *testing.T) []string {
	t.Helper()
	m, _ := filepath.Glob(filepath.Join(f.game, "bin", ".duke3d.*"))
	return m
}

func wantRefused(t *testing.T, err error, part string) {
	t.Helper()
	if err == nil || !strings.Contains(err.Error(), part) {
		t.Fatalf("want refusal containing %q, got %v", part, err)
	}
}

func TestInstallPatchesAndKeepsBackup(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if shaHex(f.read(t, "bin/duke3d")) != f.lin.patch.PatchedSHA {
		t.Fatal("executable is not the patched build")
	}
	if shaHex(f.read(t, "bin/"+f.lin.backup)) != f.lin.patch.OriginalSHA {
		t.Fatal("backup is not the original")
	}
	if st, _ := os.Stat(filepath.Join(f.game, "bin/duke3d")); runtime.GOOS != "windows" && st.Mode().Perm() != 0o751 {
		t.Fatalf("mode %o", st.Mode().Perm())
	}
	if l := f.leftovers(t); len(l) != 0 {
		t.Fatalf("temp files left: %v", l)
	}
}

func TestInstallTwiceIsNoop(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	msg, err := Install(f.patches(), f.game)
	if err != nil || !strings.Contains(msg, "already patched") {
		t.Fatalf("second install: %q %v", msg, err)
	}
}

func TestUnknownExecutableRefused(t *testing.T) {
	f := newFixture(t)
	f.write(t, "bin/duke3d", append(f.lin.original, 'x'), 0o751)
	_, err := Install(f.patches(), f.game)
	wantRefused(t, err, "unknown executable")
	if _, e := os.Stat(filepath.Join(f.game, "bin", f.lin.backup)); e == nil {
		t.Fatal("backup written for an unknown executable")
	}
}

func TestOldWordMismatchRefused(t *testing.T) {
	f := newFixture(t)
	f.lin.patch.Changes[0].Old = 0x093C28E4
	_, err := Install(f.patches(), f.game)
	wantRefused(t, err, "offset 0x00000064")
	if shaHex(f.read(t, "bin/duke3d")) != f.lin.patch.OriginalSHA {
		t.Fatal("executable changed")
	}
}

func TestWrongResultRefused(t *testing.T) {
	f := newFixture(t)
	f.lin.patch.PatchedSHA = strings.Repeat("0", 64)
	_, err := Install(f.patches(), f.game)
	wantRefused(t, err, "patched checksum")
	if shaHex(f.read(t, "bin/duke3d")) != f.lin.patch.OriginalSHA {
		t.Fatal("executable changed")
	}
	if l := f.leftovers(t); len(l) != 0 {
		t.Fatalf("temp files left: %v", l)
	}
}

func TestForeignBackupRefused(t *testing.T) {
	f := newFixture(t)
	f.write(t, "bin/"+f.lin.backup, []byte("junk"), 0o644)
	_, err := Install(f.patches(), f.game)
	wantRefused(t, err, "backup")
	if string(f.read(t, "bin/"+f.lin.backup)) != "junk" {
		t.Fatal("foreign backup replaced")
	}
}

func TestUninstallRestores(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if _, err := Uninstall(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if shaHex(f.read(t, "bin/duke3d")) != f.lin.patch.OriginalSHA {
		t.Fatal("original not restored")
	}
	if st, _ := os.Stat(filepath.Join(f.game, "bin/duke3d")); runtime.GOOS != "windows" && st.Mode().Perm() != 0o751 {
		t.Fatalf("mode %o", st.Mode().Perm())
	}
	if _, e := os.Stat(filepath.Join(f.game, "bin", f.lin.backup)); e == nil {
		t.Fatal("backup left behind")
	}
}

func TestUninstallTamperedBackupRefused(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	f.write(t, "bin/"+f.lin.backup, append(f.lin.original, 'x'), 0o755)
	_, err := Uninstall(f.patches(), f.game)
	wantRefused(t, err, "backup")
	if shaHex(f.read(t, "bin/duke3d")) != f.lin.patch.PatchedSHA {
		t.Fatal("executable changed")
	}
}

func TestUninstallUnknownRefused(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	f.write(t, "bin/duke3d", []byte("other"), 0o755)
	_, err := Uninstall(f.patches(), f.game)
	wantRefused(t, err, "unknown executable")
}

func TestStatusReportsState(t *testing.T) {
	f := newFixture(t)
	if s, _ := Status(f.patches(), f.game); s != "bin/duke3d=original" {
		t.Fatalf("status %q", s)
	}
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if s, _ := Status(f.patches(), f.game); s != "bin/duke3d=patched" {
		t.Fatalf("status %q", s)
	}
}

func TestLocateReadsLibraryFolders(t *testing.T) {
	f := newFixture(t)
	steam := filepath.Join(f.home, ".local/share/Steam")
	lib := filepath.Join(filepath.Dir(f.game), "lib2")
	if err := os.MkdirAll(filepath.Join(steam, "steamapps"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(lib, "steamapps/common"), 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(lib, "steamapps/common", GameFolder)
	if err := os.Rename(f.game, target); err != nil {
		t.Fatal(err)
	}
	vdf := fmt.Sprintf("\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"%s\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"%s\"\n\t}\n}\n", steam, lib)
	if err := os.WriteFile(filepath.Join(steam, "steamapps/libraryfolders.vdf"), []byte(vdf), 0o644); err != nil {
		t.Fatal(err)
	}
	got := Locate(f.patches(), f.home)
	if len(got) != 1 || got[0] != target {
		t.Fatalf("locate %v, want %s", got, target)
	}
}

func TestEmbeddedPatchesParse(t *testing.T) {
	ps, err := Embedded()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]int{"bin/duke3d": 353, "bin/duke3d.exe": 399}
	if len(ps) != len(want) {
		t.Fatalf("embedded %d patches", len(ps))
	}
	for _, p := range ps {
		if len(p.Changes) != want[p.Exe] || len(p.OriginalSHA) != 64 || p.Backup == "" {
			t.Fatalf("embedded patch %s: %d changes backup=%q", p.Exe, len(p.Changes), p.Backup)
		}
	}
}

func TestResolveGame(t *testing.T) {
	f := newFixture(t)
	if got, err := ResolveGame(f.patches(), f.home, f.game); err != nil || got != f.game {
		t.Fatalf("explicit dir: %q %v", got, err)
	}
	_, err := ResolveGame(f.patches(), f.home, "")
	wantRefused(t, err, "game not found")
	_, err = ResolveGame(f.patches(), f.home, filepath.Join(f.home, "nowhere"))
	wantRefused(t, err, "game not found")
}

func (f *fixture) cfg(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(f.game, "gameroot", LocalConfig))
	if err != nil {
		return "<absent>"
	}
	return string(b)
}

func TestResolutionOnMissingConfig(t *testing.T) {
	f := newFixture(t)
	if err := SetResolution(f.game, 3440, 1440); err != nil {
		t.Fatal(err)
	}
	got := f.cfg(t)
	for _, want := range []string{"[Screen Setup]", "ScreenWidth = 3440", "ScreenHeight = 1440", "ScreenMode = 1", "ScreenBPP = 32"} {
		if !strings.Contains(got, want) {
			t.Fatalf("config lacks %q:\n%s", want, got)
		}
	}
	if err := RestoreResolution(f.game); err != nil {
		t.Fatal(err)
	}
	if got := f.cfg(t); got != "<absent>" {
		t.Fatalf("config should be gone again, got:\n%s", got)
	}
}

func TestResolutionKeepsOtherSettings(t *testing.T) {
	f := newFixture(t)
	orig := "[Screen Setup]\nShadows = 1\nScreenWidth = 1920\nScreenHeight = 1080\nScreenMode = 0\nScreenGamma = 4\n"
	if err := os.MkdirAll(filepath.Join(f.game, "gameroot"), 0o755); err != nil {
		t.Fatal(err)
	}
	f.write(t, "gameroot/"+LocalConfig, []byte(orig), 0o644)
	if err := SetResolution(f.game, 3440, 1440); err != nil {
		t.Fatal(err)
	}
	got := f.cfg(t)
	for _, want := range []string{"Shadows = 1", "ScreenGamma = 4", "ScreenWidth = 3440", "ScreenHeight = 1440", "ScreenMode = 1"} {
		if !strings.Contains(got, want) {
			t.Fatalf("config lacks %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "1920") {
		t.Fatalf("old width left behind:\n%s", got)
	}
	if err := SetResolution(f.game, 2560, 1080); err != nil {
		t.Fatal(err)
	}
	if err := RestoreResolution(f.game); err != nil {
		t.Fatal(err)
	}
	if got := f.cfg(t); got != orig {
		t.Fatalf("restore changed the file:\n%s", got)
	}
}

func TestResolutionLimits(t *testing.T) {
	f := newFixture(t)
	for _, wh := range [][2]int{{3840, 2160}, {9000, 1440}, {100, 100}} {
		wantRefused(t, SetResolution(f.game, wh[0], wh[1]), "resolution")
	}
	if got := f.cfg(t); got != "<absent>" {
		t.Fatalf("refused resolution wrote a config:\n%s", got)
	}
}

func TestParseResolution(t *testing.T) {
	if w, h, err := ParseResolution("3440x1440"); err != nil || w != 3440 || h != 1440 {
		t.Fatalf("%d %d %v", w, h, err)
	}
	for _, bad := range []string{"", "3440", "3440x", "x1440", "3440*1440", "a x b"} {
		if _, _, err := ParseResolution(bad); err == nil {
			t.Fatalf("accepted %q", bad)
		}
	}
}

func TestManifestNeedsExeAndBackup(t *testing.T) {
	sums := "ORIGINAL_SHA256=" + strings.Repeat("a", 64) + "\nPATCHED_SHA256=" + strings.Repeat("b", 64) + "\n"
	for _, m := range []string{sums, sums + "EXE=bin/duke3d\n", sums + "BACKUP=x\n"} {
		_, err := ParsePatch(m, "0x0\t0x0\t0x1\tx\n")
		wantRefused(t, err, "manifest")
	}
}

func TestInstallWindowsExe(t *testing.T) {
	f := newFixture(t)
	if err := os.Remove(filepath.Join(f.game, f.lin.exe)); err != nil {
		t.Fatal(err)
	}
	f.write(t, f.win.exe, f.win.original, 0o755)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if f.sha(t, f.win.exe) != f.win.patch.PatchedSHA || f.sha(t, "bin/"+f.win.backup) != f.win.patch.OriginalSHA {
		t.Fatal("windows exe not patched with its own backup")
	}
	if s, _ := Status(f.patches(), f.game); s != "bin/duke3d.exe=patched" {
		t.Fatalf("status %q", s)
	}
	if _, err := Uninstall(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if f.sha(t, f.win.exe) != f.win.patch.OriginalSHA {
		t.Fatal("windows exe not restored")
	}
}

func TestInstallBothExes(t *testing.T) {
	f := newFixture(t)
	f.write(t, f.win.exe, f.win.original, 0o755)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if f.sha(t, f.lin.exe) != f.lin.patch.PatchedSHA || f.sha(t, f.win.exe) != f.win.patch.PatchedSHA {
		t.Fatal("both exes should be patched")
	}
	if s, _ := Status(f.patches(), f.game); s != "bin/duke3d=patched bin/duke3d.exe=patched" {
		t.Fatalf("status %q", s)
	}
	if _, err := Uninstall(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	if f.sha(t, f.lin.exe) != f.lin.patch.OriginalSHA || f.sha(t, f.win.exe) != f.win.patch.OriginalSHA {
		t.Fatal("both exes should be restored")
	}
}

func TestUnknownSecondExeRefusesAll(t *testing.T) {
	f := newFixture(t)
	f.write(t, f.win.exe, []byte("other build"), 0o755)
	_, err := Install(f.patches(), f.game)
	wantRefused(t, err, "unknown executable")
	if f.sha(t, f.lin.exe) != f.lin.patch.OriginalSHA {
		t.Fatal("native exe patched although the other one is unknown")
	}
	if _, e := os.Stat(filepath.Join(f.game, "bin", f.lin.backup)); e == nil {
		t.Fatal("backup written although the other exe is unknown")
	}
}

func TestUninstallUnknownSecondExeRefusesAll(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patches(), f.game); err != nil {
		t.Fatal(err)
	}
	f.write(t, f.win.exe, []byte("other build"), 0o755)
	_, err := Uninstall(f.patches(), f.game)
	wantRefused(t, err, "unknown executable")
	if f.sha(t, f.lin.exe) != f.lin.patch.PatchedSHA {
		t.Fatal("native exe restored although the other one is unknown")
	}
}

func TestNoGameExeRefused(t *testing.T) {
	f := newFixture(t)
	if err := os.Remove(filepath.Join(f.game, f.lin.exe)); err != nil {
		t.Fatal(err)
	}
	_, err := Install(f.patches(), f.game)
	wantRefused(t, err, "game not found")
	_, err = ResolveGame(f.patches(), f.home, f.game)
	wantRefused(t, err, "game not found")
}

func TestLocateFindsWindowsSteam(t *testing.T) {
	f := newFixture(t)
	if err := os.Remove(filepath.Join(f.game, f.lin.exe)); err != nil {
		t.Fatal(err)
	}
	f.write(t, f.win.exe, f.win.original, 0o755)
	pf := filepath.Join(filepath.Dir(f.game), "pf86")
	common := filepath.Join(pf, "Steam", "steamapps", "common")
	if err := os.MkdirAll(common, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(common, GameFolder)
	if err := os.Rename(f.game, target); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ProgramFiles(x86)", pf)
	if got := Locate(f.patches(), f.home); len(got) != 1 || got[0] != target {
		t.Fatalf("locate %v, want %s", got, target)
	}
}

func TestResolutionKeepsCRLF(t *testing.T) {
	f := newFixture(t)
	orig := "[Screen Setup]\r\nShadows = 1\r\nScreenWidth = 1920\r\nScreenHeight = 1080\r\n[Sound Setup]\r\nFXVolume = 220\r\n"
	if err := os.MkdirAll(filepath.Join(f.game, "gameroot"), 0o755); err != nil {
		t.Fatal(err)
	}
	f.write(t, "gameroot/"+LocalConfig, []byte(orig), 0o644)
	if err := SetResolution(f.game, 3440, 1440); err != nil {
		t.Fatal(err)
	}
	got := f.cfg(t)
	if strings.Count(got, "\r\n") != strings.Count(got, "\n") || !strings.Contains(got, "ScreenWidth = 3440\r\n") {
		t.Fatalf("line endings changed:\n%q", got)
	}
	if err := RestoreResolution(f.game); err != nil {
		t.Fatal(err)
	}
	if got := f.cfg(t); got != orig {
		t.Fatalf("restore changed the file:\n%q", got)
	}
}
