package engine

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type fixture struct {
	game, home        string
	original, patched []byte
	patch             Patch
}

func shaHex(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	dir := t.TempDir()
	f := &fixture{game: filepath.Join(dir, "game"), home: filepath.Join(dir, "home")}
	f.original = make([]byte, 4096)
	if _, err := rand.Read(f.original); err != nil {
		t.Fatal(err)
	}
	binary.LittleEndian.PutUint32(f.original[100:], 0x093C28E0)
	binary.LittleEndian.PutUint32(f.original[200:], 0xA00)
	f.patched = append([]byte(nil), f.original...)
	binary.LittleEndian.PutUint32(f.patched[100:], 0x098AA1C0)
	binary.LittleEndian.PutUint32(f.patched[200:], 0x2000)
	manifest := fmt.Sprintf("ORIGINAL_SHA256=%s\nPATCHED_SHA256=%s\n", shaHex(f.original), shaHex(f.patched))
	changes := "0x00000064\t0x093c28e0\t0x098aa1c0\tumost+0\n0x000000c8\t0x00000a00\t0x00002000\twidth_clamp\n"
	p, err := ParsePatch(manifest, changes)
	if err != nil {
		t.Fatal(err)
	}
	f.patch = p
	if err := os.MkdirAll(filepath.Join(f.game, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	f.write(t, "bin/duke3d", f.original, 0o751)
	return f
}

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
	if _, err := Install(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	if shaHex(f.read(t, "bin/duke3d")) != f.patch.PatchedSHA {
		t.Fatal("executable is not the patched build")
	}
	if shaHex(f.read(t, "bin/"+BackupName)) != f.patch.OriginalSHA {
		t.Fatal("backup is not the original")
	}
	if st, _ := os.Stat(filepath.Join(f.game, "bin/duke3d")); st.Mode().Perm() != 0o751 {
		t.Fatalf("mode %o", st.Mode().Perm())
	}
	if l := f.leftovers(t); len(l) != 0 {
		t.Fatalf("temp files left: %v", l)
	}
}

func TestInstallTwiceIsNoop(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	msg, err := Install(f.patch, f.game)
	if err != nil || !strings.Contains(msg, "already patched") {
		t.Fatalf("second install: %q %v", msg, err)
	}
}

func TestUnknownExecutableRefused(t *testing.T) {
	f := newFixture(t)
	f.write(t, "bin/duke3d", append(f.original, 'x'), 0o751)
	_, err := Install(f.patch, f.game)
	wantRefused(t, err, "unknown executable")
	if _, e := os.Stat(filepath.Join(f.game, "bin", BackupName)); e == nil {
		t.Fatal("backup written for an unknown executable")
	}
}

func TestOldWordMismatchRefused(t *testing.T) {
	f := newFixture(t)
	f.patch.Changes[0].Old = 0x093C28E4
	_, err := Install(f.patch, f.game)
	wantRefused(t, err, "offset 0x00000064")
	if shaHex(f.read(t, "bin/duke3d")) != f.patch.OriginalSHA {
		t.Fatal("executable changed")
	}
}

func TestWrongResultRefused(t *testing.T) {
	f := newFixture(t)
	f.patch.PatchedSHA = strings.Repeat("0", 64)
	_, err := Install(f.patch, f.game)
	wantRefused(t, err, "patched checksum")
	if shaHex(f.read(t, "bin/duke3d")) != f.patch.OriginalSHA {
		t.Fatal("executable changed")
	}
	if l := f.leftovers(t); len(l) != 0 {
		t.Fatalf("temp files left: %v", l)
	}
}

func TestForeignBackupRefused(t *testing.T) {
	f := newFixture(t)
	f.write(t, "bin/"+BackupName, []byte("junk"), 0o644)
	_, err := Install(f.patch, f.game)
	wantRefused(t, err, "backup")
	if string(f.read(t, "bin/"+BackupName)) != "junk" {
		t.Fatal("foreign backup replaced")
	}
}

func TestUninstallRestores(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	if _, err := Uninstall(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	if shaHex(f.read(t, "bin/duke3d")) != f.patch.OriginalSHA {
		t.Fatal("original not restored")
	}
	if st, _ := os.Stat(filepath.Join(f.game, "bin/duke3d")); st.Mode().Perm() != 0o751 {
		t.Fatalf("mode %o", st.Mode().Perm())
	}
	if _, e := os.Stat(filepath.Join(f.game, "bin", BackupName)); e == nil {
		t.Fatal("backup left behind")
	}
}

func TestUninstallTamperedBackupRefused(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	f.write(t, "bin/"+BackupName, append(f.original, 'x'), 0o755)
	_, err := Uninstall(f.patch, f.game)
	wantRefused(t, err, "backup")
	if shaHex(f.read(t, "bin/duke3d")) != f.patch.PatchedSHA {
		t.Fatal("executable changed")
	}
}

func TestUninstallUnknownRefused(t *testing.T) {
	f := newFixture(t)
	if _, err := Install(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	f.write(t, "bin/duke3d", []byte("other"), 0o755)
	_, err := Uninstall(f.patch, f.game)
	wantRefused(t, err, "unknown executable")
}

func TestStatusReportsState(t *testing.T) {
	f := newFixture(t)
	if s, _ := Status(f.patch, f.game); s != "original" {
		t.Fatalf("status %q", s)
	}
	if _, err := Install(f.patch, f.game); err != nil {
		t.Fatal(err)
	}
	if s, _ := Status(f.patch, f.game); s != "patched" {
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
	got := Locate(f.home)
	if len(got) != 1 || got[0] != target {
		t.Fatalf("locate %v, want %s", got, target)
	}
}

func TestEmbeddedPatchParses(t *testing.T) {
	p, err := Embedded()
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Changes) != 353 || len(p.OriginalSHA) != 64 || len(p.PatchedSHA) != 64 {
		t.Fatalf("embedded patch: %d changes", len(p.Changes))
	}
}

func TestResolveGame(t *testing.T) {
	f := newFixture(t)
	if got, err := ResolveGame(f.home, f.game); err != nil || got != f.game {
		t.Fatalf("explicit dir: %q %v", got, err)
	}
	_, err := ResolveGame(f.home, "")
	wantRefused(t, err, "game not found")
	_, err = ResolveGame(f.home, filepath.Join(f.home, "nowhere"))
	wantRefused(t, err, "game not found")
}
