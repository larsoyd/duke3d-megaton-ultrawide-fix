package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/larsoyd/duke3d-megaton-ultrawide-fix/engine"
)

const usage = "usage: duke3d-ultrawide locate|status|install|uninstall [--game-dir DIR] [--resolution WxH]"

func run(args []string, home string) (string, error) {
	if len(args) < 1 {
		return "", fmt.Errorf("refused: %s", usage)
	}
	cmd := args[0]
	fs := flag.NewFlagSet(cmd, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	dir := fs.String("game-dir", "", "game folder that contains bin/duke3d")
	res := fs.String("resolution", "", "screen size to save in the game settings, such as 3440x1440")
	if err := fs.Parse(args[1:]); err != nil {
		return "", fmt.Errorf("refused: %v, %s", err, usage)
	}
	if cmd == "locate" {
		return strings.Join(engine.Locate(home), "\n"), nil
	}
	w, h := 0, 0
	if *res != "" {
		var err error
		if w, h, err = engine.ParseResolution(*res); err != nil {
			return "", err
		}
		if err = engine.CheckResolution(w, h); err != nil {
			return "", err
		}
	}
	patch, err := engine.Embedded()
	if err != nil {
		return "", err
	}
	game, err := engine.ResolveGame(home, *dir)
	if err != nil {
		return "", err
	}
	var msg string
	switch cmd {
	case "status":
		msg, err = engine.Status(patch, game)
	case "install":
		if msg, err = engine.Install(patch, game); err == nil && w > 0 {
			if err = engine.SetResolution(game, w, h); err == nil {
				msg += fmt.Sprintf(" resolution=%dx%d", w, h)
			}
		}
	case "uninstall":
		if err = engine.RestoreResolution(game); err == nil {
			msg, err = engine.Uninstall(patch, game)
		}
	default:
		err = fmt.Errorf("refused: %s", usage)
	}
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("[duke3d-ultrawide] game=%q %s", game, msg), nil
}

func main() {
	home, err := os.UserHomeDir()
	if err == nil {
		var out string
		if out, err = run(os.Args[1:], home); err == nil {
			if out != "" {
				fmt.Println(out)
			}
			return
		}
	}
	fmt.Fprintln(os.Stderr, "[duke3d-ultrawide]", err)
	os.Exit(1)
}
