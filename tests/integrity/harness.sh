#!/usr/bin/env bash
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TAG=integrity
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

COPY="" EXE="" EXIT_TEST=0 SIZES=()
while [ $# -gt 0 ]; do
  case $1 in
    --game-copy) COPY=$(realpath "${2:?}"); shift 2 ;;
    --exe) EXE=$(realpath "${2:?}"); shift 2 ;;
    --exit-test) EXIT_TEST=1; shift ;;
    *x*) SIZES+=("$1"); shift ;;
    *) refuse "unknown argument $1" ;;
  esac
done
[ -n "$COPY" ] && [ -n "$EXE" ] && [ "${#SIZES[@]}" -gt 0 ] || refuse "usage: harness.sh --game-copy DIR --exe FILE [--exit-test] WxH..."
[ -f "$COPY/bin/duke3d" ] && [ -d "$COPY/gameroot" ] || refuse "$COPY is not a copy of the game folder"
case $COPY in */steamapps/*) refuse "$COPY is inside a Steam library, use a copy" ;; esac
for tool in Xvfb xdotool xwd magick gdb; do command -v "$tool" > /dev/null || refuse "missing $tool"; done
pgrep -x steam > /dev/null || refuse "Steam is not running, the game needs it to start"
ulimit -c 0
[ "$(ulimit -c)" = 0 ] || refuse "core dumps are still enabled"
export KDE_DEBUG=1

PATCH_DIR="$ROOT/patches/megaton-1.4.9-linux"
load_manifest
case $(sha_of "$EXE") in
  "$PATCHED_SHA") KIND=patched ;;
  "$ORIGINAL_SHA") KIND=original ;;
  *) refuse "unknown executable $EXE" ;;
esac
runtime_dir() {
  local lib
  while IFS= read -r lib; do
    [ -x "$lib/steamapps/common/$1/_v2-entry-point" ] || [ -x "$lib/steamapps/common/$1/scout-on-soldier-entry-point-v2" ] \
      && { echo "$lib/steamapps/common/$1"; return; }
  done < <(steam_libraries)
  refuse "Steam runtime $1 not found"
}
SOLDIER=$(runtime_dir SteamLinuxRuntime_soldier)
SCOUT=$(runtime_dir SteamLinuxRuntime)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/duke3d-integrity.XXXXXX")
cp -f "$EXE" "$COPY/bin/duke3d"
log "kind=$KIND out=$OUT"

DNUM=97 XPID="" GPID="" PRIV=""
stop() {
  [ -n "$GPID" ] && kill -- -"$GPID" 2> /dev/null
  [ -n "$XPID" ] && kill "$XPID" 2> /dev/null
  wait 2> /dev/null
  [ -n "$PRIV" ] && rm -rf "$PRIV"
  GPID="" XPID="" PRIV=""
}
trap 'stop' EXIT

start() {
  local size=$1 secs=$2
  Xvfb ":$DNUM" -screen 0 "${size}x24" -nolisten tcp > "$OUT/xvfb.log" 2>&1 &
  XPID=$!
  for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X$DNUM" ] && break; sleep 0.1; done
  [ -e "/tmp/.X11-unix/X$DNUM" ] || refuse "Xvfb did not start"
  PRIV=$(mktemp -d)
  mkdir -p "$PRIV/userhome" "$PRIV/run" && chmod 700 "$PRIV/run" && ln -s "$HOME/.steam" "$PRIV/userhome/.steam"
  (cd "$COPY/gameroot" && exec env -i PATH=/usr/bin:/bin HOME="$PRIV/userhome" XDG_RUNTIME_DIR="$PRIV/run" \
    DISPLAY=":$DNUM" SDL_AUDIODRIVER=dummy PULSE_SERVER=unix:/nonexistent \
    __GLX_VENDOR_LIBRARY_NAME=mesa LIBGL_ALWAYS_SOFTWARE=1 \
    setsid timeout -s KILL "$secs" "$SOLDIER/_v2-entry-point" --verb=run -- \
    "$SCOUT/scout-on-soldier-entry-point-v2" -- "$COPY/bin/duke3d.sh") > "$OUT/game.log" 2>&1 &
  GPID=$!
  sleep 25
  kill -0 "$GPID" 2> /dev/null || refuse "game exited during startup, see $OUT/game.log"
}

game_pid() { pgrep -f -n '^\.\./bin/duke3d'; }
key() { DISPLAY=":$DNUM" timeout 5 xdotool key "$@"; }
hold() { DISPLAY=":$DNUM" timeout 5 xdotool keydown "$1"; sleep "$2"; DISPLAY=":$DNUM" timeout 5 xdotool keyup "$1"; }
probe() {
  PROBE_MODE=$1 PROBE_CHANGES="$PATCH_DIR/changes.tsv" timeout 120 gdb -q -batch -ex "set debuginfod enabled off" \
    -p "$(game_pid)" -x "$HERE/probe.py" 2>&1 | grep '^\[integrity\]'
}
shot() { DISPLAY=":$DNUM" timeout 10 xwd -root -silent | timeout 30 magick xwd:- "$1"; }
view_mean() { timeout 30 magick "$1" -gravity north -crop 100%x80%+0+0 +repage -format '%[fx:mean]' info:; }
enter_game() { key Return; sleep 3; key Return; sleep 3; key Return; sleep 3; key Return; sleep 6; }
write_cfg() { printf '[Screen Setup]\nScreenWidth = %s\nScreenHeight = %s\nScreenMode = 1\nScreenBPP = 32\n' "$1" "$2" > "$COPY/gameroot/duke3d-local.cfg"; }

FAILS=0
verdict() {
  local name=$1 report=$2 img=$3 m ok=1
  m=$(view_mean "$img")
  grep -q 'ok=True' <<< "$report" || ok=0
  if [ "$KIND" = patched ]; then grep -q 'guard=check regions=[0-9]* bad=0' <<< "$report" || ok=0; fi
  awk -v m="$m" 'BEGIN{exit !(m > 0.01)}' || ok=0
  echo "$report"
  log "result size=$name view_mean=$m verdict=$([ "$ok" = 1 ] && echo pass || echo FAIL)"
  [ "$ok" = 1 ] || FAILS=$((FAILS + 1))
}

render_test() {
  local size=$1 w h report
  IFS=x read -r w h <<< "$size"
  write_cfg "$w" "$h"
  start "$size" 90
  report=""
  [ "$KIND" = patched ] && report+=$(probe fill)$'\n'
  enter_game
  hold Up 2; hold Left 1; sleep 2
  shot "$OUT/$size.png"
  report+=$(probe view)$'\n'
  [ "$KIND" = patched ] && report+=$(probe check)$'\n'
  stop
  verdict "$size" "$report" "$OUT/$size.png"
}

exit_test() {
  local size=$1 w h
  IFS=x read -r w h <<< "$size"
  rm -f "$COPY/gameroot/duke3d-local.cfg"
  start "$size" 70
  timeout 60 gdb -q -batch -ex "set debuginfod enabled off" -p "$(game_pid)" -x "$HERE/skip-cloud-upload.gdb" > "$OUT/exit-gdb.log" 2>&1 &
  sleep 3
  key Return; sleep 2; key Up; sleep 1; key Return; sleep 2; key Return; sleep 6
  if kill -0 "$GPID" 2> /dev/null; then stop; log "exit size=$size verdict=FAIL reason=still_running"; FAILS=$((FAILS + 1)); return; fi
  wait "$GPID"; local rc=$?
  GPID=""
  stop
  grep -q 'upload skipped' "$OUT/exit-gdb.log" || { log "exit verdict=FAIL reason=upload_not_intercepted"; FAILS=$((FAILS + 1)); return; }
  grep -q "^ScreenWidth = $w\$" "$COPY/gameroot/duke3d-local.cfg" 2> /dev/null \
    || { log "exit verdict=FAIL reason=config_not_saved rc=$rc"; FAILS=$((FAILS + 1)); return; }
  log "exit size=$size rc=$rc config_saved=yes verdict=pass"
}

for size in "${SIZES[@]}"; do
  if [ "$EXIT_TEST" = 1 ]; then exit_test "$size"; else render_test "$size"; fi
done
log "done kind=$KIND failures=$FAILS out=$OUT"
[ "$FAILS" = 0 ]
