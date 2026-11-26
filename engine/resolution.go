package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	LocalConfig = "duke3d-local.cfg"
	MaxWidth    = 8192
	MaxHeight   = 1600
	section     = "[Screen Setup]"
	previous    = LocalConfig + ".ultrawide-previous"
)

var screenKeys = []string{"ScreenWidth", "ScreenHeight", "ScreenMode", "ScreenBPP"}

var resolutionRE = regexp.MustCompile(`^(\d+)x(\d+)$`)

func ParseResolution(s string) (int, int, error) {
	m := resolutionRE.FindStringSubmatch(s)
	if m == nil {
		return 0, 0, refused("resolution %q is not WIDTHxHEIGHT", s)
	}
	w, _ := strconv.Atoi(m[1])
	h, _ := strconv.Atoi(m[2])
	return w, h, nil
}

func keyOf(line string) string {
	k, _, ok := strings.Cut(line, "=")
	if !ok {
		return ""
	}
	return strings.TrimSpace(k)
}

func readLines(path string) ([]string, string, bool, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, "\n", false, nil
	}
	if err != nil {
		return nil, "", false, err
	}
	eol := "\n"
	if strings.Contains(string(b), "\r\n") {
		eol = "\r\n"
	}
	return strings.Split(strings.TrimSuffix(string(b), eol), eol), eol, true, nil
}

func writeLines(path string, lines []string, eol string) error {
	return writeBeside(path, []byte(strings.Join(lines, eol)+eol), 0o644)
}

func sectionBounds(lines []string) (int, int) {
	start := -1
	for i, l := range lines {
		t := strings.TrimSpace(l)
		if start < 0 && t == section {
			start = i
		} else if start >= 0 && strings.HasPrefix(t, "[") {
			return start, i
		}
	}
	return start, len(lines)
}

// setKeys replaces or adds lines in the screen section, an empty value removes the key.
func setKeys(lines []string, values map[string]string) []string {
	start, end := sectionBounds(lines)
	if start < 0 {
		lines = append(lines, section)
		start, end = len(lines)-1, len(lines)
	}
	done := map[string]bool{}
	var out []string
	out = append(out, lines[:start+1]...)
	for _, l := range lines[start+1 : end] {
		if v, ok := values[keyOf(l)]; ok {
			done[keyOf(l)] = true
			if v != "" {
				out = append(out, v)
			}
			continue
		}
		out = append(out, l)
	}
	for _, k := range screenKeys {
		if v, ok := values[k]; ok && !done[k] && v != "" {
			out = append(out, v)
		}
	}
	return append(out, lines[end:]...)
}

func CheckResolution(w, h int) error {
	if w < 320 || h < 200 || w > MaxWidth || h > MaxHeight {
		return refused("resolution %dx%d is outside %dx%d to %dx%d", w, h, 320, 200, MaxWidth, MaxHeight)
	}
	return nil
}

func SetResolution(game string, w, h int) error {
	if err := CheckResolution(w, h); err != nil {
		return err
	}
	dir := filepath.Join(game, "gameroot")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	cfg := filepath.Join(dir, LocalConfig)
	lines, eol, exists, err := readLines(cfg)
	if err != nil {
		return err
	}
	state := filepath.Join(dir, previous)
	if _, err := os.Stat(state); os.IsNotExist(err) {
		saved := []string{fmt.Sprintf("file=%t", exists)}
		start, end := sectionBounds(lines)
		for _, k := range screenKeys {
			line := ""
			for i := start + 1; start >= 0 && i < end; i++ {
				if keyOf(lines[i]) == k {
					line = lines[i]
				}
			}
			saved = append(saved, k+"\t"+line)
		}
		if err := writeLines(state, saved, "\n"); err != nil {
			return err
		}
	}
	return writeLines(cfg, setKeys(lines, map[string]string{
		"ScreenWidth": fmt.Sprintf("ScreenWidth = %d", w), "ScreenHeight": fmt.Sprintf("ScreenHeight = %d", h),
		"ScreenMode": "ScreenMode = 1", "ScreenBPP": "ScreenBPP = 32"}), eol)
}

func RestoreResolution(game string) error {
	dir := filepath.Join(game, "gameroot")
	state := filepath.Join(dir, previous)
	saved, _, ok, err := readLines(state)
	if err != nil || !ok {
		return err
	}
	cfg := filepath.Join(dir, LocalConfig)
	lines, eol, _, err := readLines(cfg)
	if err != nil {
		return err
	}
	values := map[string]string{}
	for _, s := range saved[1:] {
		k, v, _ := strings.Cut(s, "\t")
		values[k] = v
	}
	lines = setKeys(lines, values)
	if saved[0] == "file=false" && len(lines) == 1 && strings.TrimSpace(lines[0]) == section {
		err = os.Remove(cfg)
	} else {
		err = writeLines(cfg, lines, eol)
	}
	if err != nil {
		return err
	}
	return os.Remove(state)
}
