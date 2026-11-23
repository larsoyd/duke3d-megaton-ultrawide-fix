# duke3d-megaton-ultrawide-fix

Lets the native Linux build of Duke Nukem 3D: Megaton Edition (Steam) run at resolutions wider than 2560 pixels, such as 3440x1440.

Without it the game world turns black at those widths and only the menus and the status bar are drawn.

This is an unofficial fix. It changes the game executable you already have, keeps a backup of the original and can be undone.

## Why the screen goes black

Megaton Edition is built on [JFBuild](https://github.com/jonof/jfbuild), a port of the Build engine. The engine sets a maximum screen width of 2560 in `jfbuild/build.h` (`MAXXDIM`) and sizes 15 per-column buffers to it: `umost`, `dmost`, `startumost`, `startdmost`, `bakumost`, `bakdmost`, `uplc`, `dplc`, `uwall`, `dwall`, `swplc`, `lplc`, `swall`, `lwall` and `radarang2`.

`setview()` and `drawrooms()` in `jfbuild/engine.c` fill those buffers for every column on screen. At 3440 columns they run 880 entries past the end and overwrite the variables stored after them. One of them is `ydimen`, the height of the 3D view. With a height of 0 the camera projection and fog break down, and walls, floors and sprites all come out black.

The width limit exists in the code, but it doesn't take effect. `checkvideomode()` clamps the width to 2560, then picks the closest mode the display offers, which on an ultrawide is 3440 again. `setgamemode()` also keeps the width that was asked for.

At 2561 to 2562 pixels the picture still looks normal. The overflow is smaller there and overwrites the sky scale (`parallaxyscale`) and other variables instead of the view height.

## What the patch changes

- The 15 buffers move to new memory with room for 8192 columns. That memory is added at the end of the program's data segment, so no existing data moves.
- The 350 places in the code that point at the old buffers are updated. `patches/megaton-1.4.9-linux/changes.tsv` lists each changed value with its file offset.
- The width limit in `checkvideomode()` goes from 2560 to 8192.
- A 64-byte gap sits after each moved buffer. The integrity test checks that these gaps stay untouched.

At 2560 pixels and below the game draws the same picture as before.

## Requirements

- Duke Nukem 3D: Megaton Edition from Steam, the native Linux version (Steam app 225140, build 610450).
- A 64-bit Linux desktop with glibc 2.28 or newer, which covers Ubuntu 20.04, Debian 10, Fedora 29, SteamOS 3 and anything newer. On Wayland the installer window runs through XWayland.
- No root access.

The fix works with this executable:

| file | checksum |
| --- | --- |
| original `bin/duke3d` sha256 | `3caf660ad2df2e55fbaf60b9fca6afa6e1f5e17e402c37b39a6579bcc67c68db` |
| patched `bin/duke3d` sha256 | `0f3a86db7084036a28043cfd37d6bdf2c36cbd7cee4292e65990196ee1df66c2` |

It leaves any other version alone. The Windows build and the 20th Anniversary World Tour edition are different programs and aren't supported.

## Install

Quit the game, then download `DukeNukem3D-Megaton-UltrawideFix-1.0.0.tar.gz` from the [releases page](https://github.com/larsoyd/duke3d-megaton-ultrawide-fix/releases), extract it and double-click the installer inside.

The release also has the installer as a bare `.run` file. A downloaded file is never marked as a program, so mark it first in your file manager (Properties > Permissions) or run:

```sh
chmod +x DukeNukem3D-Megaton-UltrawideFix-1.0.0.run
./DukeNukem3D-Megaton-UltrawideFix-1.0.0.run
```

The installer asks for two things:

- The game folder. It fills this in when the game is in the default Steam library, otherwise use Browse.
- The resolution. It fills this in from your main screen. The game then starts at that size without a trip to the video menu. Leave it empty to keep the game's own setting.

It installs a small helper and an uninstaller in `~/.local/share/duke3d-megaton-ultrawide-fix`, then patches the game:

1. Checks the checksum of `bin/duke3d`. It stops if the file is a version it doesn't know.
2. Copies the original to `bin/duke3d.megaton-original` and checks the copy.
3. Builds the patched file next to the game, checks its checksum and moves it into place.
4. Writes the resolution to `gameroot/duke3d-local.cfg` and keeps the previous values.

## Uninstall

Run `~/.local/share/duke3d-megaton-ultrawide-fix/uninstall-ultrawide-fix` and choose to remove everything. It puts the original game file and your previous screen settings back. If the backup is gone, Steam can restore the original with Properties > Installed Files > Verify integrity of game files.

## Without the graphical installer

The same fix is available as shell scripts, which need `xdelta3` (Arch: `pacman -S xdelta3`, Debian or Ubuntu: `apt install xdelta3`):

```sh
git clone https://github.com/larsoyd/duke3d-megaton-ultrawide-fix
cd duke3d-megaton-ultrawide-fix
./install.sh
./uninstall.sh
```

`install.sh` looks for the game in your Steam libraries, including extra library folders and Flatpak Steam. Give it `--game-dir` with the game folder if it finds more than one copy or none. The scripts don't change the resolution, so pick it in the game's video options and quit through the menu to save it.

The helper the graphical installer uses also works on its own: `duke3d-ultrawide install --game-dir DIR --resolution 3440x1440`, and `duke3d-ultrawide uninstall --game-dir DIR`.

## Tested resolutions

Run with the integrity test in this repository, fullscreen, on a virtual X display with software OpenGL inside Steam's Linux runtime:

| resolution | original | patched |
| --- | --- | --- |
| 1920x1080 | works | works |
| 2559x1440 | works | works |
| 2560x1440 | works | works |
| 2561x1440 | looks fine, overwrites other variables | works |
| 3440x1440 | black world | works |
| 3840x1600 | black world | works |

Quitting through the menu at 3440x1440 saves the mode to `gameroot/duke3d-local.cfg`, and the next start uses it.

The engine has a separate height limit of 1600 pixels that this patch doesn't change, so taller modes such as 3840x2160 aren't supported.

## Steam updates and file verification

Megaton Edition has been off sale since 2016 and its build hasn't changed since. If Steam updates the game, or you verify the game files, the original executable comes back. Run the installer again afterwards.

## Troubleshooting

- `refused: unknown executable`: the game is a different build, or something else has changed it. Verify the game files in Steam and try again.
- `refused: game not found`: add `--game-dir` with the folder that contains `bin/duke3d`.
- `refused: backup ... is not the original`: there is already a different file called `duke3d.megaton-original`. Move it somewhere else and run the installer again.
- `xdelta3 is not installed` from `install.sh`: install the `xdelta3` package, or use the graphical installer.
- The installer doesn't start and mentions a missing `libxcb` or `libxkbcommon` library: install your distribution's Qt or X11 runtime packages, or use `install.sh`.
- The game starts at the wrong resolution: it saves video settings when you quit through its menu. Closing the window another way loses them.

## How it's built and tested

- `patches/megaton-1.4.9-linux/manifest` has the checksums and file names.
- `patches/megaton-1.4.9-linux/changes.tsv` lists every change.
- `tools/make_patch.py ORIGINAL OUT` builds the patched executable from the original and the change list, checking each old value and both checksums. You can use it to rebuild the patch yourself.
- `tests/test_install.sh` runs the installer and uninstaller against fake game folders: wrong checksums, a damaged patch file, a wrong result, an existing foreign backup, permissions, and finding the game in Steam libraries.
- `tests/test_make_patch.py` tests the build tool the same way.
- `engine/` is the helper the graphical installer runs, with its own tests (`go test ./...`). `installer/` is the Qt Installer Framework package around it.
- `tests/lint.sh` runs ShellCheck.
- `tests/integrity/harness.sh` starts the real game from a copy of the game folder on a virtual display with sound off, enters a level and checks the view size and the gaps after the moved buffers. It also checks a screenshot of the 3D view. With `--exit-test` it quits through the menu and checks that the settings file was written. It needs Steam running, plus `Xvfb`, `xdotool`, `gdb` and ImageMagick. It won't run on a folder inside a Steam library, and it doesn't upload anything to Steam Cloud.

```sh
cp -a "$HOME/.local/share/Steam/steamapps/common/Duke Nukem 3D" /tmp/duke-copy
python3 tools/make_patch.py /tmp/duke-copy/bin/duke3d /tmp/duke3d-patched
bash tests/integrity/harness.sh --game-copy /tmp/duke-copy --exe /tmp/duke3d-patched 2561x1440 3440x1440
```

## Repository contents

Scripts, the installer sources, documentation and a 1.7 KB patch file. The patch file holds the new address values and instructions to copy everything else from your own executable. It contains no game code, and the repository has no game files.

## Credits

Duke Nukem 3D was made by 3D Realms. The Build engine is by Ken Silverman. JFBuild and JFDuke3D are by Jonathon Fowler. Megaton Edition was ported by Gennadiy Potapov and published by Devolver Digital. Its source is at [github.com/TermiT/duke3d-megaton](https://github.com/TermiT/duke3d-megaton). This project isn't affiliated with any of them, and the game names and trademarks belong to their owners.

## License

The scripts, tools, tests and documentation here are under the MIT License, see `LICENSE`. It covers this project's own files, not the game.
