#!/bin/sh
# Copyright 2026 The FreedomChat authors
# SPDX-License-Identifier: Apache-2.0
# Source coverage of the library (checks mode) under the differential suite, with
# GNATcoverage (gnatcov, source instrumentation): statement, decision and MC/DC coverage of
# src/unishox.adb, and of Encode_Char and Decode_Step on their own. The instrumented build
# is relocated to tests/build/cov/tree, so obj/ and the other test builds are untouched.
# Prints the summaries and every violation; the annotated sources are in tests/build/cov/xcov.
# Local only (gnatcov is not in the CI image).
# Usage: tests/coverage.sh [round trips (default 100000)] [decoder fuzz cases (default 100000)]
# Environment:
#   GNATCOV  the gnatcov program (default: gnatcov on PATH; a binary release comes with
#            `alr -n get gnatcov_bin`)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
. "$ROOT/env.sh"
GNATCOV=${GNATCOV:-$(command -v gnatcov || true)}
[ -n "$GNATCOV" ] && [ -x "$GNATCOV" ] \
  || { echo "gnatcov not found: set GNATCOV (alr -n get gnatcov_bin fetches it)" >&2; exit 2; }
C="$HERE/build/cov"
mkdir -p "$C/tree"
# The C half of the coverage runtime is built by GNAT's gcc, which needs the SDK headers
[ -n "${SDKROOT:-}" ] && { C_INCLUDE_PATH="$SDKROOT/usr/include"; export C_INCLUDE_PATH; }
GPR_PROJECT_PATH="$C/rts/share/gpr${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"; export GPR_PROJECT_PATH

"$HERE/build-ref.sh"
[ -f "$C/rts/share/gpr/gnatcov_rts.gpr" ] \
  || (cd "$C" && "$GNATCOV" setup --prefix="$C/rts" > "$C/setup.log" 2>&1) \
  || { tail -20 "$C/setup.log"; exit 1; }

P="-P $HERE/tests.gpr -XUNISHOX_BUILD_MODE=checks --relocate-build-tree --root-dir=$ROOT"
cd "$C/tree"
"$GNATCOV" instrument $P --level=stmt+mcdc --projects=unishox_spark > "$C/instrument.log" 2>&1 \
  || { tail -20 "$C/instrument.log"; exit 1; }
gprbuild -q -p $P --src-subdirs=gnatcov-instr --implicit-with=gnatcov_rts > "$C/build.log" 2>&1 \
  || { grep -v 'deployment version\|newer macOS' "$C/build.log"; exit 1; }
rm -f "$C"/*.srctrace
(cd "$C" && "$C/tree/tests/build/checks/test_unishox" "$HERE/corpus.txt" "${1:-100000}" "${2:-100000}" \
   > "$C/test.log") || { tail -20 "$C/test.log"; exit 1; }
tail -2 "$C/test.log"

for level in stmt+decision stmt+mcdc; do
  echo "== $level"
  rm -rf "$C/xcov"
  "$GNATCOV" coverage $P --level=$level --projects=unishox_spark --annotate=xcov \
    --output-dir="$C/xcov" "$C"/*.srctrace > /dev/null 2>&1
  "$GNATCOV" coverage $P --level=$level --projects=unishox_spark --annotate=report \
    -o "$C/report-$level.txt" "$C"/*.srctrace
  sed -n '2,4p' "$C/xcov/unishox.adb.xcov" | sed 's/^/  unishox.adb: /'
  for sp in Encode_Char Decode_Step; do
    line=$(grep -n "^   procedure $sp\$" "$ROOT/src/unishox.adb" | cut -d: -f1)
    rm -rf "$C/sp"
    "$GNATCOV" coverage $P --level=$level --projects=unishox_spark --annotate=xcov \
      --subprograms="$ROOT/src/unishox.adb:$line" --output-dir="$C/sp" "$C"/*.srctrace > /dev/null 2>&1
    sed -n '3,5p' "$C/sp/unishox.adb.xcov" | grep -v '^$' | sed "s/^/  $sp: /"
  done
  grep -E '^unishox[.a-z-]*:[0-9]+:[0-9]+: ' "$C/report-$level.txt" | sed 's/^/  /' || true
done
rm -rf "$C/xcov"
"$GNATCOV" coverage $P --level=stmt+mcdc --projects=unishox_spark --annotate=xcov \
  --output-dir="$C/xcov" "$C"/*.srctrace > /dev/null 2>&1
