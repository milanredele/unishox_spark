#!/bin/sh
# Copyright 2026 The FreedomChat authors
# SPDX-License-Identifier: Apache-2.0
# Builds the C reference (reference/unishox2.c, -fwrapv because malformed input can overflow
# its int arithmetic) and tests/c/ref_wrap.c with clang into tests/build/libunishox2_ref.a.
# Used by run.sh, exhaustive.sh and coverage.sh.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
B="$HERE/build"
mkdir -p "$B"
clang -O2 -fwrapv -w -DUNISHOX_API_WITH_OUTPUT_LEN=1 -I"$ROOT/reference" \
  -c "$ROOT/reference/unishox2.c" -o "$B/unishox2.o"
clang -O2 -Wall -DUNISHOX_API_WITH_OUTPUT_LEN=1 -I"$ROOT/reference" \
  -c "$HERE/c/ref_wrap.c" -o "$B/ref_wrap.o"
rm -f "$B/libunishox2_ref.a"
ar rcs "$B/libunishox2_ref.a" "$B/unishox2.o" "$B/ref_wrap.o"
