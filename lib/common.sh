#!/usr/bin/env bash
GAME_NAME="Duke Nukem 3D"
BACKUP_NAME=duke3d.megaton-original

log() { echo "[$TAG] $*"; }
refuse() { echo "[$TAG] refused: $*" >&2; exit 1; }
sha_of() { sha256sum "$1" | cut -d' ' -f1; }

parse_args() {
  GAME_DIR=""
  PATCH_DIR="$ROOT/patches/megaton-1.4.9-linux"
  while [ $# -gt 0 ]; do
    case $1 in
      --game-dir) GAME_DIR=${2:?--game-dir needs a value}; shift 2 ;;
      --patch-dir) PATCH_DIR=${2:?--patch-dir needs a value}; shift 2 ;;
      -h|--help) echo "usage: $0 [--game-dir DIR] [--patch-dir DIR]"; exit 0 ;;
      *) refuse "unknown argument $1" ;;
    esac
  done
}

manifest_value() {
  local key=$1 value
  value=$(grep -E "^$key=" "$PATCH_DIR/manifest" | head -1 | cut -d= -f2-)
  [ -n "$value" ] || refuse "manifest has no $key"
  echo "$value"
}

load_manifest() {
  [ -f "$PATCH_DIR/manifest" ] || refuse "no manifest in $PATCH_DIR"
  ORIGINAL_SHA=$(manifest_value ORIGINAL_SHA256)
  PATCHED_SHA=$(manifest_value PATCHED_SHA256)
  DELTA="$PATCH_DIR/$(manifest_value DELTA)"
  DELTA_SHA=$(manifest_value DELTA_SHA256)
}

steam_libraries() {
  local root vdf
  for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [ -d "$root/steamapps" ] || continue
    echo "$root"
    vdf="$root/steamapps/libraryfolders.vdf"
    [ -f "$vdf" ] && sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$vdf"
  done
}

locate_game() {
  if [ -n "$GAME_DIR" ]; then
    [ -f "$GAME_DIR/bin/duke3d" ] || refuse "game not found: no bin/duke3d in $GAME_DIR"
    return
  fi
  local lib found=()
  while IFS= read -r lib; do
    local dir="$lib/steamapps/common/$GAME_NAME"
    [ -f "$dir/bin/duke3d" ] && found+=("$(realpath "$dir")")
  done < <(steam_libraries)
  mapfile -t found < <(printf '%s\n' "${found[@]}" | sort -u | sed '/^$/d')
  [ "${#found[@]}" -gt 0 ] || refuse "game not found in any Steam library, pass --game-dir"
  [ "${#found[@]}" -eq 1 ] || refuse "several installs found (${found[*]}), pass --game-dir"
  GAME_DIR=${found[0]}
}

replace_atomically() {
  local src=$1 dest=$2 tmp
  tmp=$(mktemp "$(dirname "$dest")/.duke3d.XXXXXX")
  TMP_FILES+=("$tmp")
  cp "$src" "$tmp"
  chmod --reference="$dest" "$tmp"
  mv -f "$tmp" "$dest"
}

TMP_FILES=()
cleanup() { [ "${#TMP_FILES[@]}" -gt 0 ] && rm -f "${TMP_FILES[@]}"; return 0; }
trap cleanup EXIT
