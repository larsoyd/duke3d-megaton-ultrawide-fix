#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
TAG=install
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

parse_args "$@"
command -v xdelta3 > /dev/null || refuse "xdelta3 is not installed"
load_manifest
locate_game
EXE="$GAME_DIR/bin/duke3d"
BACKUP="$GAME_DIR/bin/$BACKUP_NAME"
log "game=$GAME_DIR"

current=$(sha_of "$EXE")
if [ "$current" = "$PATCHED_SHA" ]; then
  log "already patched sha256=$current"
  exit 0
fi
[ "$current" = "$ORIGINAL_SHA" ] || refuse "unknown executable sha256=$current, expected $ORIGINAL_SHA"
[ "$(sha_of "$DELTA")" = "$DELTA_SHA" ] || refuse "delta checksum does not match the manifest"

if [ -e "$BACKUP" ]; then
  [ "$(sha_of "$BACKUP")" = "$ORIGINAL_SHA" ] || refuse "backup $BACKUP exists and is not the original"
else
  tmp=$(mktemp "$GAME_DIR/bin/.duke3d.XXXXXX")
  TMP_FILES+=("$tmp")
  cp -p "$EXE" "$tmp"
  mv -n "$tmp" "$BACKUP"
  [ "$(sha_of "$BACKUP")" = "$ORIGINAL_SHA" ] || refuse "backup did not verify"
  log "backup=$BACKUP"
fi

out=$(mktemp "$GAME_DIR/bin/.duke3d.XXXXXX")
TMP_FILES+=("$out")
timeout 120 xdelta3 -d -f -s "$EXE" "$DELTA" "$out" || refuse "xdelta3 failed"
got=$(sha_of "$out")
[ "$got" = "$PATCHED_SHA" ] || refuse "patched checksum $got does not match $PATCHED_SHA"
chmod --reference="$EXE" "$out"
mv -f "$out" "$EXE"
log "patched sha256=$got"
