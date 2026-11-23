#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
TAG=uninstall
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

parse_args "$@"
load_manifest
locate_game
EXE="$GAME_DIR/bin/duke3d"
BACKUP="$GAME_DIR/bin/$BACKUP_NAME"
log "game=$GAME_DIR"

current=$(sha_of "$EXE")
if [ "$current" = "$ORIGINAL_SHA" ]; then
  log "not patched, nothing to restore"
  exit 0
fi
[ "$current" = "$PATCHED_SHA" ] || refuse "unknown executable sha256=$current, leaving it alone"
[ -f "$BACKUP" ] || refuse "backup $BACKUP is missing, use Steam to verify the game files"
[ "$(sha_of "$BACKUP")" = "$ORIGINAL_SHA" ] || refuse "backup $BACKUP does not match the original"

replace_atomically "$BACKUP" "$EXE"
[ "$(sha_of "$EXE")" = "$ORIGINAL_SHA" ] || refuse "restore did not verify"
rm -f "$BACKUP"
log "restored sha256=$ORIGINAL_SHA"
