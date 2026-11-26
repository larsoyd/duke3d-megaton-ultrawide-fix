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
[ -n "$COPY" ] && [ -n "$EXE" ] && [ "${#SIZES[@]}" -gt 0 ] || refuse "usage: harness-windows.sh --game-copy DIR --exe FILE [--exit-test] WxH..."
[ -f "$COPY/bin/duke3d.exe" ] && [ -d "$COPY/gameroot" ] || refuse "$COPY is not a copy of the Windows game folder"
case $COPY in */steamapps/*) refuse "$COPY is inside a Steam library, use a copy" ;; esac
for tool in Xvfb xdotool xwd magick python3; do command -v "$tool" > /dev/null || refuse "missing $tool"; done
pgrep -x steam > /dev/null || refuse "Steam is not running, the game needs it to start"
ulimit -c 0
[ "$(ulimit -c)" = 0 ] || refuse "core dumps are still enabled"
export KDE_DEBUG=1

PATCH_DIR="$ROOT/patches/megaton-1.4.9-windows"
KIND=original
if [ -f "$PATCH_DIR/manifest" ]; then
  ORIGINAL_SHA=$(manifest_value ORIGINAL_SHA256)
  PATCHED_SHA=$(manifest_value PATCHED_SHA256)
  case $(sha_of "$EXE") in
    "$PATCHED_SHA") KIND=patched ;;
    "$ORIGINAL_SHA") KIND=original ;;
    *) refuse "unknown executable $EXE" ;;
  esac
fi
tool_dir() {
  local lib
  while IFS= read -r lib; do
    [ -e "$lib/steamapps/common/$1/$2" ] && { echo "$lib/steamapps/common/$1"; return; }
  done < <(steam_libraries)
  refuse "$1 not found"
}
PROTON=$(tool_dir "Proton - Experimental" proton)
RUNTIME=$(tool_dir SteamLinuxRuntime_4 _v2-entry-point)
STEAM_ROOT=$(realpath "$HOME/.steam/root")
OUT=$(mktemp -d "${TMPDIR:-/tmp}/duke3d-integrity-win.XXXXXX")
PFX="$OUT/prefix"
mkdir -p "$PFX"
printf 'pcm.!default { type null }\nctl.!default { type hw card 0 }\n' > "$OUT/asound.conf"
cp -f "$EXE" "$COPY/bin/duke3d.exe"
# a crash in the copy must not offer to send a report
for f in "$COPY"/bin/CrashSender1402.exe "$COPY"/gameroot/CrashSender1402.exe; do
  [ -e "$f" ] && mv -f "$f" "$f.disabled"
done
log "kind=$KIND out=$OUT"

DNUM=96 XPID="" GPID="" PRIV=""
stop() {
  [ -n "$GPID" ] && kill -- -"$GPID" 2> /dev/null
  [ -n "$XPID" ] && kill "$XPID" 2> /dev/null
  wait 2> /dev/null
  [ -n "$PRIV" ] && rm -rf "$PRIV"
  GPID="" XPID="" PRIV=""
}
trap 'stop' EXIT

probe() { PROBE_CHANGES="$PATCH_DIR/changes.tsv" PROBE_WAIT="${2:-1}" timeout 150 python3 -I "$HERE/probe-windows.py" "$1" "$PFX"; }

start() {
  local size=$1 secs=$2
  Xvfb ":$DNUM" -screen 0 "${size}x24" -nolisten tcp > "$OUT/xvfb.log" 2>&1 &
  XPID=$!
  for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X$DNUM" ] && break; sleep 0.1; done
  [ -e "/tmp/.X11-unix/X$DNUM" ] || refuse "Xvfb did not start"
  PRIV=$(mktemp -d)
  mkdir -p "$PRIV/userhome" "$PRIV/run" && chmod 700 "$PRIV/run" && ln -s "$HOME/.steam" "$PRIV/userhome/.steam"
  (cd "$COPY/gameroot" && exec env -i PATH=/usr/bin:/bin HOME="$PRIV/userhome" XDG_RUNTIME_DIR="$PRIV/run" \
    DISPLAY=":$DNUM" SDL_AUDIODRIVER=dummy PULSE_SERVER=unix:/nonexistent ALSA_CONFIG_PATH="$OUT/asound.conf" \
    WINEDLLOVERRIDES="winepulse.drv=d" __GLX_VENDOR_LIBRARY_NAME=mesa LIBGL_ALWAYS_SOFTWARE=1 \
    STEAM_COMPAT_DATA_PATH="$PFX" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    SteamAppId=225140 SteamGameId=225140 STEAM_COMPAT_APP_ID=225140 \
    setsid timeout -s KILL "$secs" "$RUNTIME/_v2-entry-point" --verb=waitforexitandrun -- \
    "$PROTON/proton" waitforexitandrun "$COPY/bin/duke3d.exe") > "$OUT/game.log" 2>&1 &
  GPID=$!
  probe pid 120 || refuse "game did not start, see $OUT/game.log"
  sleep 20
  kill -0 "$GPID" 2> /dev/null || refuse "game exited during startup, see $OUT/game.log"
}

key() { DISPLAY=":$DNUM" timeout 5 xdotool key "$@"; }
hold() { DISPLAY=":$DNUM" timeout 5 xdotool keydown "$1"; sleep "$2"; DISPLAY=":$DNUM" timeout 5 xdotool keyup "$1"; }
shot() { DISPLAY=":$DNUM" timeout 10 xwd -root -silent | timeout 30 magick xwd:- "$1"; }
view_mean() { timeout 30 magick "$1" -gravity north -crop 100%x80%+0+0 +repage -format '%[fx:mean]' info:; }
enter_game() { key Return; sleep 3; key Return; sleep 3; key Return; sleep 3; key Return; sleep 8; }
write_cfg() { printf '[Screen Setup]\r\nScreenWidth = %s\r\nScreenHeight = %s\r\nScreenMode = 1\r\nScreenBPP = 32\r\n' "$1" "$2" > "$COPY/gameroot/duke3d-local.cfg"; }

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
  start "$size" 150
  report=""
  [ "$KIND" = patched ] && report+=$(probe fill)$'\n'
  enter_game
  hold Up 2; hold Left 1; sleep 2
  shot "$OUT/$size.png"
  if kill -0 "$GPID" 2> /dev/null; then
    report+=$(probe view)$'\n'
    [ "$KIND" = patched ] && report+=$(probe check)$'\n'
  else
    report+="[integrity] game exited before the view check"$'\n'
  fi
  stop
  verdict "$size" "$report" "$OUT/$size.png"
}

exit_test() {
  local size=$1 w h
  IFS=x read -r w h <<< "$size"
  rm -f "$COPY/gameroot/duke3d-local.cfg"
  start "$size" 150
  probe nocloud || { stop; log "exit verdict=FAIL reason=upload_not_disabled"; FAILS=$((FAILS + 1)); return; }
  key Return; sleep 2; key Up; sleep 1; key Return; sleep 2; key Return; sleep 10
  if kill -0 "$GPID" 2> /dev/null; then stop; log "exit size=$size verdict=FAIL reason=still_running"; FAILS=$((FAILS + 1)); return; fi
  wait "$GPID"; local rc=$?
  GPID=""
  stop
  grep -q "^ScreenWidth = $w"$'\r'"\?\$" "$COPY/gameroot/duke3d-local.cfg" 2> /dev/null \
    || { log "exit verdict=FAIL reason=config_not_saved rc=$rc"; FAILS=$((FAILS + 1)); return; }
  log "exit size=$size rc=$rc config_saved=yes crlf=$(grep -c $'\r' "$COPY/gameroot/duke3d-local.cfg") verdict=pass"
}

for size in "${SIZES[@]}"; do
  if [ "$EXIT_TEST" = 1 ]; then exit_test "$size"; else render_test "$size"; fi
done
log "done kind=$KIND failures=$FAILS out=$OUT"
[ "$FAILS" = 0 ]
