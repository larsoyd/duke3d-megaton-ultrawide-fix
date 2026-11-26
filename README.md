# duke3d-megaton-ultrawide-fix

<p align="center">
  <img src="docs/screenshot-3440x1440.jpg" alt="Duke Nukem 3D: Megaton Edition running at 3440x1440" width="720">
</p>

Lets the now discontinued [Duke Nukem 3D: Megaton Edition](https://www.pcgamingwiki.com/wiki/Duke_Nukem_3D:_Megaton_Edition) (Steam) run at resolutions wider than 2560 pixels, such as 3440x1440. It works with the native Linux build and with the Windows build, on Windows or on Linux through Proton.

Without it the native Linux game draws a black world at those widths, with only the menus and the status bar showing, and the Windows game crashes.

Ultrawide here means wide screens up to 1600 pixels tall, such as 3440x1440 or 3840x1600. Taller ultrawide modes such as 5120x2160 aren't covered, and there are no plans to cover them for now.

This is an unofficial fix. It changes the game executable you already have, keeps a backup of the original and can be undone.

## Why the screen goes black

Megaton Edition is built on [JFBuild](https://github.com/jonof/jfbuild), a port of the Build engine. The engine sets a maximum screen width of 2560 in `jfbuild/build.h` (`MAXXDIM`) and sizes 15 per-column buffers to it: `umost`, `dmost`, `startumost`, `startdmost`, `bakumost`, `bakdmost`, `uplc`, `dplc`, `uwall`, `dwall`, `swplc`, `lplc`, `swall`, `lwall` and `radarang2`.

`setview()` and `drawrooms()` in `jfbuild/engine.c` fill those buffers for every column on screen. At 3440 columns they run 880 entries past the end and overwrite the variables stored after them. One of them is `ydimen`, the height of the 3D view. With a height of 0 the camera projection and fog break down, and walls, floors and sprites all come out black.

The width limit exists in the code, but it doesn't take effect. `checkvideomode()` clamps the width to 2560, then picks the closest mode the display offers, which on an ultrawide is 3440 again. `setgamemode()` also keeps the width that was asked for.

At 2561 to 2562 pixels the picture still looks normal. The overflow is smaller there and overwrites the sky scale (`parallaxyscale`) and other variables instead of the view height.

The Windows build has the same buffers, but its compiler put other variables after them. There the overflow hits the view window, the SDL window and the visibility settings, and the game crashes at 3440x1440.

## What the patch changes

- The 15 buffers move to new memory with room for 8192 columns. In the Linux build that memory is added at the end of the program's data segment. In the Windows build it is a new section after the last one. Either way no existing data moves.
- The places in the code that point at the old buffers are updated, 350 in the Linux build and 390 in the Windows build. `patches/megaton-1.4.9-linux/changes.tsv` and `patches/megaton-1.4.9-windows/changes.tsv` list each changed value with its file offset.
- The width limit in `checkvideomode()` goes from 2560 to 8192.
- A 64-byte gap sits after each moved buffer. The integrity test checks that these gaps stay untouched.

At 2560 pixels and below the game draws the same picture as before.

## Requirements

- Duke Nukem 3D: Megaton Edition from Steam (Steam app 225140, build 610450), either the native Linux version or the Windows version.
- On Linux: a 64-bit desktop with glibc 2.28 or newer, which covers Ubuntu 20.04, Debian 10, Fedora 29, SteamOS 3 and anything newer. On Wayland the installer window runs through XWayland. If you play the Windows version through Proton, use the Linux installer. It finds `bin/duke3d.exe` in the same game folder.
- On Windows: 64-bit Windows 10 or 11.
- No root access. On Windows the installer asks for no administrator rights.

The fix works with these executables:

| file | checksum |
| --- | --- |
| original `bin/duke3d` sha256 | `3caf660ad2df2e55fbaf60b9fca6afa6e1f5e17e402c37b39a6579bcc67c68db` |
| patched `bin/duke3d` sha256 | `0f3a86db7084036a28043cfd37d6bdf2c36cbd7cee4292e65990196ee1df66c2` |
| original `bin/duke3d.exe` sha256 | `0782cf3803b847f55ec06c031eb6046c0f9edd1b49b31db30673254b99704d45` |
| patched `bin/duke3d.exe` sha256 | `6feb94dbb140bbc57a371da42979dc4ef0bb6e1b2d89ff3a88bfb11a64045d0a` |

It leaves any other version alone. The 20th Anniversary World Tour edition is a different program and isn't supported.

## Install

Quit the game first. The installers are on the [releases page](https://github.com/larsoyd/duke3d-megaton-ultrawide-fix/releases).

### Linux

Download `DukeNukem3D-Megaton-UltrawideFix-1.1.0.tar.gz`, extract it and double-click the installer inside.

The release also has the installer as a bare `.run` file. A downloaded file is never marked as a program, so mark it first in your file manager (Properties > Permissions) or run:

```sh
chmod +x DukeNukem3D-Megaton-UltrawideFix-1.1.0.run
./DukeNukem3D-Megaton-UltrawideFix-1.1.0.run
```

### Windows

Download `DukeNukem3D-Megaton-UltrawideFix-1.1.0.exe` and run it. The installer isn't signed, so Windows may show a "Windows protected your PC" box. Choose More info, then Run anyway.

### What the installer does

It asks for two things:

- The game folder. It fills this in when the game is in the default Steam library, otherwise use Browse.
- The resolution. It fills this in from your main screen. The game then starts at that size without a trip to the video menu. Leave it empty to keep the game's own setting.

It installs a small helper and an uninstaller in `~/.local/share/duke3d-megaton-ultrawide-fix` on Linux, or `%LOCALAPPDATA%\duke3d-megaton-ultrawide-fix` on Windows, then patches the game:

1. Checks the checksum of `bin/duke3d` or `bin/duke3d.exe`. It stops if the file is a version it doesn't know.
2. Copies the original to `bin/duke3d.megaton-original` or `bin/duke3d.exe.megaton-original` and checks the copy.
3. Builds the patched file next to the game, checks its checksum and moves it into place.
4. Writes the resolution to `gameroot/duke3d-local.cfg` and keeps the previous values.

## Uninstall

On Linux, run `~/.local/share/duke3d-megaton-ultrawide-fix/uninstall-ultrawide-fix` and choose to remove everything. On Windows, remove "Duke Nukem 3D Megaton Ultrawide Fix" in Settings > Apps > Installed apps, or run `uninstall-ultrawide-fix.exe` in its folder.

It puts the original game file and your previous screen settings back. If the backup is gone, Steam can restore the original with Properties > Installed Files > Verify integrity of game files.

## Without the graphical installer

The same fix is available as shell scripts, which need `xdelta3` (Arch: `pacman -S xdelta3`, Debian or Ubuntu: `apt install xdelta3`):

```sh
git clone https://github.com/larsoyd/duke3d-megaton-ultrawide-fix
cd duke3d-megaton-ultrawide-fix
./install.sh
./uninstall.sh
```

`install.sh` looks for the game in your Steam libraries, including extra library folders and Flatpak Steam. Give it `--game-dir` with the game folder if it finds more than one copy or none. The scripts don't change the resolution, so pick it in the game's video options and quit through the menu to save it. They only handle the native Linux build.

The helper the graphical installer uses also works on its own, with either build: `duke3d-ultrawide install --game-dir DIR --resolution 3440x1440`, and `duke3d-ultrawide uninstall --game-dir DIR`.

## Tested resolutions

Run with the integrity tests in this repository, fullscreen, on a virtual X display with software OpenGL. The Linux build runs inside Steam's Linux runtime, the Windows build through Proton Experimental:

| resolution | Linux original | Linux patched | Windows original | Windows patched |
| --- | --- | --- | --- | --- |
| 1920x1080 | works | works | works | works |
| 2559x1440 | works | works | works | works |
| 2560x1440 | works | works | works | works |
| 2561x1440 | looks fine, overwrites other variables | works | black screen | works |
| 3440x1440 | black world | works | crashes | works |
| 3840x1600 | black world | works | crashes | works |

With either build, quitting through the menu at 3440x1440 saves the mode to `gameroot/duke3d-local.cfg`, and the next start uses it.

The engine has a separate height limit of 1600 pixels that this patch doesn't change, so taller modes such as 3840x2160 aren't supported.

## Steam updates and file verification

Megaton Edition has been off sale since 2016 and its build hasn't changed since. If Steam updates the game, or you verify the game files, the original executable comes back. Run the installer again afterwards.

## Troubleshooting

- `refused: unknown executable`: the game is a different build, or something else has changed it. Verify the game files in Steam and try again.
- `refused: game not found`: add `--game-dir` with the folder that contains `bin/duke3d` or `bin/duke3d.exe`.
- `refused: backup ... is not the original`: there is already a different file called `duke3d.megaton-original` or `duke3d.exe.megaton-original`. Move it somewhere else and run the installer again.
- Access denied on Windows: the game is still running, or something else has the game file open. Quit it and run the installer again.
- `xdelta3 is not installed` from `install.sh`: install the `xdelta3` package, or use the graphical installer.
- The installer doesn't start and mentions a missing `libxcb` or `libxkbcommon` library: install your distribution's Qt or X11 runtime packages, or use `install.sh`.
- The game starts at the wrong resolution: it saves video settings when you quit through its menu. Closing the window another way loses them.

## How it's built and tested

- `patches/megaton-1.4.9-linux/` and `patches/megaton-1.4.9-windows/` each have a `manifest` with the checksums and file names and a `changes.tsv` that lists every change.
- `tools/make_patch.py ORIGINAL OUT` builds the patched executable from the original and the change list, checking each old value and both checksums. You can use it to rebuild the patch yourself. Add `--patch-dir patches/megaton-1.4.9-windows` for `duke3d.exe`.
- `tests/test_install.sh` runs the installer and uninstaller against fake game folders: wrong checksums, a damaged patch file, a wrong result, an existing foreign backup, permissions, and finding the game in Steam libraries.
- `tests/test_make_patch.py` tests the build tool the same way.
- `engine/` is the helper the graphical installer runs, with its own tests (`go test ./...`). `installer/` is the Qt Installer Framework package around it.
- `tests/lint.sh` runs ShellCheck.
- `tests/integrity/harness.sh` starts the real game from a copy of the game folder on a virtual display with sound off, enters a level and checks the view size and the gaps after the moved buffers. It also checks a screenshot of the 3D view. With `--exit-test` it quits through the menu and checks that the settings file was written. It needs Steam running, plus `Xvfb`, `xdotool`, `gdb` and ImageMagick. It won't run on a folder inside a Steam library, and it doesn't upload anything to Steam Cloud.
- `tests/integrity/harness-windows.sh` does the same for `duke3d.exe` through Proton Experimental, with a fresh Wine prefix for each run.

```sh
cp -a "$HOME/.local/share/Steam/steamapps/common/Duke Nukem 3D" /tmp/duke-copy
python3 tools/make_patch.py /tmp/duke-copy/bin/duke3d /tmp/duke3d-patched
bash tests/integrity/harness.sh --game-copy /tmp/duke-copy --exe /tmp/duke3d-patched 2561x1440 3440x1440
```

## Repository contents

Scripts, the installer sources, documentation, a screenshot, the two change tables and a 1.7 KB patch file. The patch file holds the new address values and instructions to copy everything else from your own executable. None of them contain game code, and the repository has no game files.

## Credits

Duke Nukem 3D was made by 3D Realms. The Build engine is by Ken Silverman. JFBuild and JFDuke3D are by Jonathon Fowler. Megaton Edition was ported by Gennadiy Potapov and published by Devolver Digital. Its source analyzed purely for this patch is at [github.com/TermiT/duke3d-megaton](https://github.com/TermiT/duke3d-megaton). This project isn't affiliated with any of them, and the game names and trademarks belong to their owners.

## License

The scripts, tools, tests and documentation here are under the MIT License, see `LICENSE`. It covers this project's own files, not the game.
