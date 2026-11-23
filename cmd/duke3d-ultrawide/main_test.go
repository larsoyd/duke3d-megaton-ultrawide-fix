package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBadResolutionLeavesGameAlone(t *testing.T) {
	game := filepath.Join(t.TempDir(), "game")
	if err := os.MkdirAll(filepath.Join(game, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(game, "bin", "duke3d")
	if err := os.WriteFile(exe, []byte("not the game"), 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := run([]string{"install", "--game-dir", game, "--resolution", "3840x2160"}, t.TempDir())
	if err == nil || !strings.Contains(err.Error(), "resolution") {
		t.Fatalf("want a resolution refusal before anything else, got %v", err)
	}
}
