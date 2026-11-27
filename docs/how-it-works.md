# How the fix works

## Why the screen goes black

Megaton Edition is built on [JFBuild](https://github.com/jonof/jfbuild), a port of the Build engine. The game sets the maximum screen width in the engine to 2560 in `jfbuild/build.h` (`MAXXDIM`) and sizes 15 per-column buffers to it: `umost`, `dmost`, `startumost`, `startdmost`, `bakumost`, `bakdmost`, `uplc`, `dplc`, `uwall`, `dwall`, `swplc`, `lplc`, `swall`, `lwall` and `radarang2`.

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
