# Testing

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

## How it's built and tested

- `patches/megaton-1.4.9-linux/` and `patches/megaton-1.4.9-windows/` each have a `manifest` with the checksums and file names and a `changes.tsv` that lists every change.
- `tools/make_patch.py ORIGINAL OUT` builds the patched executable from the original and the change list, checking each old value and both checksums. You can use it to rebuild the patch yourself. Add `--patch-dir patches/megaton-1.4.9-windows` for `duke3d.exe`.
- `tests/test_install.sh` runs the installer and uninstaller against fake game folders: wrong checksums, a damaged patch file, a wrong result, an existing foreign backup, permissions, and finding the game in Steam libraries.
- `tests/test_make_patch.py` tests the build tool the same way.
- `tests/install.Tests.ps1` runs the Pester tests for `install.ps1` and `uninstall.ps1` the same way, plus a locked game file on Windows and a check of the real Windows change table against an independent apply. CI runs it in Windows PowerShell 5.1 and PowerShell 7.
- `engine/` is the helper the graphical installer runs, with its own tests (`go test ./...`). `installer/` is the Qt Installer Framework package around it.
- `tests/lint.sh` runs ShellCheck.
- `tests/integrity/harness.sh` starts the real game from a copy of the game folder on a virtual display with sound off, enters a level and checks the view size and the gaps after the moved buffers. It also checks a screenshot of the 3D view. With `--exit-test` it quits through the menu and checks that the settings file was written. It needs Steam running, plus `Xvfb`, `xdotool`, `gdb` and ImageMagick. It won't run on a folder inside a Steam library, and it doesn't upload anything to Steam Cloud.
- `tests/integrity/harness-windows.sh` does the same for `duke3d.exe` through Proton Experimental, with a fresh Wine prefix for each run.

```sh
cp -a "$HOME/.local/share/Steam/steamapps/common/Duke Nukem 3D" /tmp/duke-copy
python3 tools/make_patch.py /tmp/duke-copy/bin/duke3d /tmp/duke3d-patched
bash tests/integrity/harness.sh --game-copy /tmp/duke-copy --exe /tmp/duke3d-patched 2561x1440 3440x1440
```
