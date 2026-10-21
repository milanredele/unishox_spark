#!/bin/sh
# Prove absence of run-time errors (and the contracts) with GNATprove at level 2.
# gnatprove is taken from $GNATPROVE, then PATH, then the Alire cache
# (`alr get gnatprove` or `alr with gnatprove` puts it there).
# Usage: ./prove.sh [extra gnatprove switches]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
if [ -z "${GNATPROVE:-}" ]; then
  GNATPROVE=$(command -v gnatprove 2>/dev/null || true)
fi
if [ -z "$GNATPROVE" ]; then
  GNATPROVE=$(ls -d "$HOME"/.local/share/alire/releases/gnatprove_*/bin/gnatprove \
                    "$HOME"/.cache/alire/releases/gnatprove_*/bin/gnatprove 2>/dev/null | tail -1 || true)
fi
[ -n "$GNATPROVE" ] || { echo "gnatprove not found: set GNATPROVE=<path>/bin/gnatprove" >&2; exit 2; }
echo "using $("$GNATPROVE" --version | head -1)"

STATUS=0
"$GNATPROVE" -P "$HERE/unishox_spark.gpr" -XUNISHOX_BUILD_MODE=release \
  --level=2 --mode=all -j0 --report=fail --output=oneline --checks-as-errors=on \
  --warnings=continue "$@" || STATUS=$?

OUT="$HERE/obj/release/gnatprove/gnatprove.out"
[ -f "$OUT" ] && sed -n '/^Summary of SPARK analysis/,/^Total/p' "$OUT"
exit $STATUS
