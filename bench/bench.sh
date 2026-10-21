#!/bin/sh
# Object size of the release build (native GNAT, -O2 -gnatp, light-runtime restrictions)
# and throughput on 1 kB inputs, next to the C reference (clang -O2).
# Usage: bench/bench.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
. "$ROOT/env.sh"
B="$HERE/build"
mkdir -p "$B"

"$ROOT/build.sh" release
echo "== object sizes (text+data, bytes; stripped file size)"
for o in "$ROOT"/obj/release/unishox.o "$ROOT"/obj/release/unishox-tables.o; do
  cp "$o" "$B/s.o"; strip -x -S "$B/s.o" 2>/dev/null || strip -x "$B/s.o"
  printf '  %-22s %s; stripped file %s\n' "$(basename "$o")" \
    "$(size "$o" | awk 'NR==2 {print "text " $1 ", data " $2}')" "$(wc -c < "$B/s.o" | tr -d ' ')"
done

clang -O2 -fwrapv -w -DUNISHOX_API_WITH_OUTPUT_LEN=1 -I"$ROOT/reference" \
  -c "$ROOT/reference/unishox2.c" -o "$B/unishox2.o"
clang -O2 -DUNISHOX_API_WITH_OUTPUT_LEN=1 -I"$ROOT/reference" \
  -c "$ROOT/tests/c/ref_wrap.c" -o "$B/ref_wrap.o"
cp "$B/unishox2.o" "$B/s.o"; strip -x -S "$B/s.o" 2>/dev/null || strip -x "$B/s.o"
printf '  %-22s %s; stripped file %s\n' "unishox2.o (C, clang)" \
  "$(size "$B/unishox2.o" | awk 'NR==2 {print "text " $1 ", data " $2}')" "$(wc -c < "$B/s.o" | tr -d ' ')"
rm -f "$B/libunishox2_ref.a" "$B/s.o"
ar rcs "$B/libunishox2_ref.a" "$B/unishox2.o" "$B/ref_wrap.o"

gprbuild -q -p -P "$HERE/bench.gpr" -XUNISHOX_BUILD_MODE=bench > "$B/build.log" 2>&1 \
  || { grep -v 'deployment version' "$B/build.log"; exit 1; }
echo "== throughput, 1 kB inputs (microseconds per call)"
"$B/bench_unishox" "$ROOT/tests/corpus.txt"
