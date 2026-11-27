# <p align="center">Duke Nukem 3D: Megaton Edition - Ultrawide Fix</p>

<table align="center"><tr><td>
  <img src="docs/screenshot-3440x1440.jpg" alt="Duke Nukem 3D: Megaton Edition running at 3440x1440" width="560">
</td></tr></table>

<p align="center">
  <a href="https://github.com/larsoyd/duke3d-megaton-ultrawide-fix/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/larsoyd/duke3d-megaton-ultrawide-fix/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
</p>

This is a binary patch that allows [Duke Nukem 3D: Megaton Edition](https://www.pcgamingwiki.com/wiki/Duke_Nukem_3D:_Megaton_Edition) (Steam) to run at resolutions wider than 2560 pixels, such as 3440x1440. It works with the native Linux build and with the Windows build, on Windows or on Linux through Proton. 

Currently the game crashes or renders with a black screen except for the HUD depending on what version & resolution you are playing with on ultrawide resolutions. This is unlikely to be patched since the game itself has sadly been removed from all storefronts, including Steam. This fix exists for those who still owns the game on Steam and who wish to play it on ultrawide resolutions. 

This is an unofficial fix with an unprivileged GUI installer. It ships with zero game code/assets. The installer only changes the game executable from Steam that you already have and then keeps a backup of the original. This can be undone by either restoring the backup or verifying integrity of game files.

The main issue fixed is that the engine sizes its per-column drawing buffers for screens only up to 2560 pixels wide, wider screens overrun them. This fix moves those buffers to new memory with room for 8192 columns and then raises the width limit. The details are in [docs/how-it-works.md](docs/how-it-works.md), and the tested resolutions and the test tools in [docs/testing.md](docs/testing.md).

**NOTE:** Ultrawide here means ultrawide screens up to 1600 pixels tall, such as 3440x1440 or 3840x1600. Taller ultrawide modes such as 5120x2160 aren't covered and will still break, there are no plans to cover them for now.

---

## Requirements

- Duke Nukem 3D: Megaton Edition from Steam (Steam app 225140, build 610450), either the native **Linux** version or the **Windows** version.
- The macOS version is **not** supported due to the game itself being 32-bit and thus officially unsupported on modern Macs. 
  
- On Linux: a 64-bit desktop with glibc 2.28 or newer. This covers Ubuntu 20.04, Debian 10, Fedora 29, SteamOS 3 and anything newer. On Wayland the installer window runs through XWayland.
- On Windows: 64-bit Windows 10 or 11.

---

The fix only works with these executable checksums which are checked by the installer:

Linux:
| file | checksum |
| --- | --- |
| original `bin/duke3d` sha256 | `3caf660ad2df2e55fbaf60b9fca6afa6e1f5e17e402c37b39a6579bcc67c68db` |
| patched `bin/duke3d` sha256 | `0f3a86db7084036a28043cfd37d6bdf2c36cbd7cee4292e65990196ee1df66c2` |

Windows:
| file | checksum |
| --- | --- |
| original `bin/duke3d.exe` sha256 | `0782cf3803b847f55ec06c031eb6046c0f9edd1b49b31db30673254b99704d45` |
| patched `bin/duke3d.exe` sha256 | `6feb94dbb140bbc57a371da42979dc4ef0bb6e1b2d89ff3a88bfb11a64045d0a` |

Any failure is most likely because you are using an **unsupported/modified version of the game.** Verify the game files in Steam and try again.


## Install

The installers are on the [releases page](https://github.com/larsoyd/duke3d-megaton-ultrawide-fix/releases). The game must not be running when doing this operation.

### Windows

Download `DukeNukem3D-Megaton-UltrawideFix-1.1.1.exe` and run it. The installer isn't signed, so Windows may show a "Windows protected your PC" box. Choose More info, then Run anyway.

### Linux

Download `DukeNukem3D-Megaton-UltrawideFix-1.1.1.tar.gz`, extract it and double-click the installer inside. 

**NB:** If you play with the Windows version through Proton you should still use the Linux installer. I have written it so it finds & fixes `bin/duke3d.exe` in the same game folder on Linux as well. When you install a new runner, i.e if you switch the game from the Native version to Proton you need to run the installer again to patch the new binary.


The release also has the installer as a bare `.run` file. A downloaded file is never marked as a program, so mark it first in your file manager (Properties > Permissions) or run:

```sh
chmod +x DukeNukem3D-Megaton-UltrawideFix-1.1.1.run
./DukeNukem3D-Megaton-UltrawideFix-1.1.1.run
```

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


## Steam updates 

A hypothetical update to the game that did not fix this issue would cause your game to be broken again as it would overwrite the patched binary, however this is highly unlikely to occur since Megaton Edition has been delisted from Steam & its build has sat abandoned for over a decade. If this happens I will update the installer to target the new binary, and all that will be needed is to run it again.

## Troubleshooting

- `refused: unknown executable`: the game is a different build, or something else has changed it. Verify the game files in Steam and try again.
- `refused: game not found`: add `--game-dir` with the folder that contains `bin/duke3d` or `bin/duke3d.exe`.
- `refused: backup ... is not the original`: there is already a different file called `duke3d.megaton-original` or `duke3d.exe.megaton-original`. Move it somewhere else and run the installer again.
- Access denied on Windows: the game is still running, or something else has the game file open. Quit it and run the installer again.
- `xdelta3 is not installed` from `install.sh`: install the `xdelta3` package, or use the graphical installer.
- The installer doesn't start and mentions a missing `libxcb` or `libxkbcommon` library: install your distribution's Qt or X11 runtime packages, or use `install.sh`.
- The game starts at the wrong resolution: it saves video settings when you quit through its menu. Closing the window another way loses them.

## Without the graphical installer 

If the GUI fails you can try to run the helper that the graphical installer uses. It works on its own with either build on Windows and Linux. Replace DIR with the directory path. Do note that on Windows it's unsigned, so SmartScreen will warn, and nobody can read it before running it.

* On Linux in your Terminal: `duke3d-ultrawide install --game-dir DIR --resolution 3440x1440`, and `duke3d-ultrawide uninstall --game-dir DIR` in your terminal. 

* On Windows in Powershell: `duke3d-ultrawide.exe install --game-dir DIR --resolution 3440x1440`, and `duke3d-ultrawide.exe uninstall --game-dir DIR`

---

If the installer still gives you grief, you can try the same fix as a shell script:

### Linux

The shell script needs `xdelta3` to function, install it from your distro's repositories (Arch: `$ pacman -S xdelta3`, Debian or Ubuntu: `$ apt install xdelta3`):

```sh
git clone https://github.com/larsoyd/duke3d-megaton-ultrawide-fix
cd duke3d-megaton-ultrawide-fix
./install.sh
./uninstall.sh
```

`install.sh` looks for the game in your Steam libraries, including extra library folders and Flatpak Steam. Give it `--game-dir` with the game folder if it finds more than one copy or none. The scripts don't change the resolution, so pick it in the game's video options and quit through the menu to save it. They only handle the native Linux build.

### Windows

TODO

## Notes

I am aware that the HUD does not fill out the sides of the screen. That remains an open cosmetic regression, but it's largely a harmless visual bug that does not hamper gameplay. 

I opted to keep the fix focused on rendering the game successfully, however a sub-mod  for this  by anyone willing to do it would be very welcomed and linked to & credited here.

## Credits

Duke Nukem 3D was made by 3D Realms. The Build engine is by Ken Silverman. JFBuild and JFDuke3D are by Jonathon Fowler. Megaton Edition was ported by Gennadiy Potapov and published by Devolver Digital. Its source analyzed purely for this patch is at [github.com/TermiT/duke3d-megaton](https://github.com/TermiT/duke3d-megaton). This project isn't affiliated with any of them, and the game names and trademarks belong to their owners.

## License

The scripts, tools, tests and documentation here are under the MIT License, see `LICENSE`. It covers this project's own files, not the game.
