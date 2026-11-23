#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

sha() { sha256sum "$1" | cut -d' ' -f1; }
ok() { PASS=$((PASS + 1)); echo "[test] pass $1"; }
bad() { FAIL=$((FAIL + 1)); echo "[test] FAIL $1: $2"; }

make_fixture() {
  local dir=$1
  mkdir -p "$dir/game/bin" "$dir/patch"
  head -c 65536 /dev/urandom > "$dir/game/bin/duke3d"
  chmod 0751 "$dir/game/bin/duke3d"
  cp "$dir/game/bin/duke3d" "$dir/original"
  cp "$dir/original" "$dir/patched"
  printf '\x00\x20\x00\x00' | dd of="$dir/patched" bs=1 seek=100 conv=notrunc status=none
  timeout 60 xdelta3 -e -9 -S none -f -s "$dir/original" "$dir/patched" "$dir/patch/duke3d.xdelta"
  {
    echo "ORIGINAL_SHA256=$(sha "$dir/original")"
    echo "PATCHED_SHA256=$(sha "$dir/patched")"
    echo "DELTA=duke3d.xdelta"
    echo "DELTA_SHA256=$(sha "$dir/patch/duke3d.xdelta")"
  } > "$dir/patch/manifest"
}

install() { timeout 120 bash "$ROOT/install.sh" --game-dir "$1/game" --patch-dir "$1/patch"; }
uninstall() { timeout 120 bash "$ROOT/uninstall.sh" --game-dir "$1/game" --patch-dir "$1/patch"; }
leftovers() { find "$1/game/bin" -name '.duke3d.*' | wc -l; }

t_install_patches() {
  local d=$WORK/install; make_fixture "$d"
  install "$d" > "$d/log" 2>&1 || { bad install "exit $?: $(tail -1 "$d/log")"; return; }
  [ "$(sha "$d/game/bin/duke3d")" = "$(sha "$d/patched")" ] || { bad install "patched hash differs"; return; }
  [ "$(stat -c %a "$d/game/bin/duke3d")" = 751 ] || { bad install "mode $(stat -c %a "$d/game/bin/duke3d")"; return; }
  cmp -s "$d/game/bin/duke3d.megaton-original" "$d/original" || { bad install "backup differs from original"; return; }
  [ "$(leftovers "$d")" = 0 ] || { bad install "temp files left"; return; }
  ok install
}

t_install_twice_is_noop() {
  local d=$WORK/twice; make_fixture "$d"
  install "$d" > /dev/null 2>&1
  install "$d" > "$d/log" 2>&1 || { bad twice "second run exit $?"; return; }
  grep -q 'already patched' "$d/log" || { bad twice "no already patched message"; return; }
  [ "$(sha "$d/game/bin/duke3d")" = "$(sha "$d/patched")" ] || { bad twice "hash changed"; return; }
  ok twice
}

t_unknown_original_refused() {
  local d=$WORK/unknown; make_fixture "$d"
  printf 'x' >> "$d/game/bin/duke3d"
  local before; before=$(sha "$d/game/bin/duke3d")
  if install "$d" > "$d/log" 2>&1; then bad unknown "accepted an unknown executable"; return; fi
  grep -q 'refused: unknown executable' "$d/log" || { bad unknown "message: $(tail -1 "$d/log")"; return; }
  [ "$(sha "$d/game/bin/duke3d")" = "$before" ] || { bad unknown "file changed"; return; }
  [ ! -e "$d/game/bin/duke3d.megaton-original" ] || { bad unknown "backup written"; return; }
  ok unknown
}

t_corrupt_delta_refused() {
  local d=$WORK/corrupt; make_fixture "$d"
  printf 'x' >> "$d/patch/duke3d.xdelta"
  if install "$d" > "$d/log" 2>&1; then bad corrupt "accepted a corrupt delta"; return; fi
  grep -q 'refused: delta checksum' "$d/log" || { bad corrupt "message: $(tail -1 "$d/log")"; return; }
  cmp -s "$d/game/bin/duke3d" "$d/original" || { bad corrupt "file changed"; return; }
  ok corrupt
}

t_patched_mismatch_refused() {
  local d=$WORK/mismatch; make_fixture "$d"
  sed -i "s/^PATCHED_SHA256=.*/PATCHED_SHA256=$(printf '0%.0s' $(seq 64))/" "$d/patch/manifest"
  if install "$d" > "$d/log" 2>&1; then bad mismatch "accepted a wrong result"; return; fi
  grep -q 'refused: patched checksum' "$d/log" || { bad mismatch "message: $(tail -1 "$d/log")"; return; }
  cmp -s "$d/game/bin/duke3d" "$d/original" || { bad mismatch "file changed"; return; }
  [ "$(leftovers "$d")" = 0 ] || { bad mismatch "temp files left"; return; }
  ok mismatch
}

t_bad_backup_refused() {
  local d=$WORK/badbackup; make_fixture "$d"
  echo junk > "$d/game/bin/duke3d.megaton-original"
  if install "$d" > "$d/log" 2>&1; then bad badbackup "overwrote a foreign backup"; return; fi
  grep -q 'refused: backup' "$d/log" || { bad badbackup "message: $(tail -1 "$d/log")"; return; }
  [ "$(cat "$d/game/bin/duke3d.megaton-original")" = junk ] || { bad badbackup "backup replaced"; return; }
  ok badbackup
}

t_uninstall_restores() {
  local d=$WORK/restore; make_fixture "$d"
  install "$d" > /dev/null 2>&1
  uninstall "$d" > "$d/log" 2>&1 || { bad restore "exit $?: $(tail -1 "$d/log")"; return; }
  cmp -s "$d/game/bin/duke3d" "$d/original" || { bad restore "original not restored"; return; }
  [ "$(stat -c %a "$d/game/bin/duke3d")" = 751 ] || { bad restore "mode $(stat -c %a "$d/game/bin/duke3d")"; return; }
  [ ! -e "$d/game/bin/duke3d.megaton-original" ] || { bad restore "backup left behind"; return; }
  ok restore
}

t_uninstall_tampered_backup_refused() {
  local d=$WORK/tampered; make_fixture "$d"
  install "$d" > /dev/null 2>&1
  printf 'x' >> "$d/game/bin/duke3d.megaton-original"
  if uninstall "$d" > "$d/log" 2>&1; then bad tampered "restored from a bad backup"; return; fi
  grep -q 'refused: backup' "$d/log" || { bad tampered "message: $(tail -1 "$d/log")"; return; }
  [ "$(sha "$d/game/bin/duke3d")" = "$(sha "$d/patched")" ] || { bad tampered "executable changed"; return; }
  ok tampered
}

t_uninstall_unknown_current_refused() {
  local d=$WORK/foreign; make_fixture "$d"
  install "$d" > /dev/null 2>&1
  echo other > "$d/game/bin/duke3d"
  if uninstall "$d" > "$d/log" 2>&1; then bad foreign "replaced an unknown executable"; return; fi
  grep -q 'refused: unknown executable' "$d/log" || { bad foreign "message: $(tail -1 "$d/log")"; return; }
  [ "$(cat "$d/game/bin/duke3d")" = other ] || { bad foreign "executable changed"; return; }
  ok foreign
}

t_locates_steam_library() {
  local d=$WORK/locate; make_fixture "$d"
  local home=$d/home lib=$d/lib2
  mkdir -p "$home/.local/share/Steam/steamapps" "$lib/steamapps/common"
  mv "$d/game" "$lib/steamapps/common/Duke Nukem 3D"
  printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' \
    "$home/.local/share/Steam" "$lib" > "$home/.local/share/Steam/steamapps/libraryfolders.vdf"
  HOME=$home timeout 120 bash "$ROOT/install.sh" --patch-dir "$d/patch" > "$d/log" 2>&1 \
    || { bad locate "exit $?: $(tail -1 "$d/log")"; return; }
  [ "$(sha "$lib/steamapps/common/Duke Nukem 3D/bin/duke3d")" = "$(sha "$d/patched")" ] || { bad locate "not patched"; return; }
  ok locate
}

t_missing_game_refused() {
  local d=$WORK/missing; mkdir -p "$d/home"
  make_fixture "$d"
  if HOME=$d/home timeout 120 bash "$ROOT/install.sh" --patch-dir "$d/patch" > "$d/log" 2>&1; then
    bad missing "succeeded without a game"; return
  fi
  grep -q 'refused: game not found' "$d/log" || { bad missing "message: $(tail -1 "$d/log")"; return; }
  ok missing
}

for t in $(declare -F | awk '{print $3}' | grep '^t_'); do "$t"; done
echo "[test] passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
