#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
rc=0
timeout 120 shellcheck -x install.sh uninstall.sh tests/*.sh || rc=1
# the lib sets globals its callers read and uses ROOT from them
timeout 120 shellcheck -s bash -e SC2034,SC2153 lib/common.sh || rc=1
echo "[lint] result=$([ "$rc" = 0 ] && echo ok || echo fail)"
exit "$rc"
