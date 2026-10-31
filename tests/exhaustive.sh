#!/bin/sh
# Copyright 2026 The FreedomChat authors
# SPDX-License-Identifier: Apache-2.0
# Bounded-exhaustive differential test (tests/src/exhaustive_unishox.adb) against the
# library with all run-time checks and contracts enabled: the decoder on every input of 1 to
# 3 bytes at the output limits 0, 1, 7, 64 and 4096, and the full check on every input of at
# most 2 bytes and every 3-byte string over a 40-character alphabet. About 20 s.
# Usage: tests/exhaustive.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
. "$ROOT/env.sh"
B="$HERE/build"
mkdir -p "$B"
"$HERE/build-ref.sh"
gprbuild -q -p -P "$HERE/tests.gpr" -XUNISHOX_BUILD_MODE=checks > "$B/build-checks.log" 2>&1 \
  || { grep -v 'deployment version' "$B/build-checks.log"; exit 1; }
"$B/checks/exhaustive_unishox"
