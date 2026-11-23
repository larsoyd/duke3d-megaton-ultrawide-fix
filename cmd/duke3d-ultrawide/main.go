package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/larsoyd/duke3d-megaton-ultrawide-fix/engine"
)

const usage = "usage: duke3d-ultrawide locate|status|install|uninstall [--game-dir DIR]"

func fail(err error) {
	fmt.Fprintln(os.Stderr, "[duke3d-ultrawide]", err)
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		fail(fmt.Errorf("refused: %s", usage))
	}
	cmd := os.Args[1]
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	dir := fs.String("game-dir", "", "game folder that contains bin/duke3d")
	fs.Parse(os.Args[2:])
	home, err := os.UserHomeDir()
	if err != nil {
		fail(err)
	}
	if cmd == "locate" {
		for _, d := range engine.Locate(home) {
			fmt.Println(d)
		}
		return
	}
	patch, err := engine.Embedded()
	if err != nil {
		fail(err)
	}
	game, err := engine.ResolveGame(home, *dir)
	if err != nil {
		fail(err)
	}
	var msg string
	switch cmd {
	case "status":
		msg, err = engine.Status(patch, game)
	case "install":
		msg, err = engine.Install(patch, game)
	case "uninstall":
		msg, err = engine.Uninstall(patch, game)
	default:
		err = fmt.Errorf("refused: %s", usage)
	}
	if err != nil {
		fail(err)
	}
	fmt.Printf("[duke3d-ultrawide] game=%q %s\n", game, msg)
}
