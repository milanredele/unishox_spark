#!/bin/sh
# Cross-compile the library with GNAT-LLVM for iOS and Android (arm64), as
# experiments/ada-cross-poc/build-llvm.sh does: one compiler, --target=<triple>, an LP64
# target-parameters file dumped from the native Alire GNAT, the light-runtime restrictions
# (unishox.adc), checks off (-gnatp, allowed because absence of run-time errors is proved).
# Then checks that the objects need nothing but memcpy/memset. On Apple targets LLVM's
# AArch64 back end lowers a memset of zeros with a variable size to bzero (libSystem),
# which is accepted as the same thing.
# Usage: ./build-target.sh   (toolchain: AWP=~/.local/share/etcs-dmi/adawebpack-native)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
AWP=${AWP:-$HOME/.local/share/etcs-dmi/adawebpack-native}
WORK="$HERE/build/target"
rm -rf "$WORK"; mkdir -p "$WORK"

# 64-bit target parameters from the native GNAT (its own target is LP64 aarch64)
printf 'package X is end X;\n' > "$WORK/x.ads"
(cd "$WORK" && "$GNAT_BIN/gcc" -c -gnatet="$WORK/lp64.atp" x.ads -o x.o 2>/dev/null || true)
[ -s "$WORK/lp64.atp" ] || { echo "could not dump lp64.atp" >&2; exit 1; }

NM=$(xcrun --find nm 2>/dev/null || command -v nm)
SIZE=$(xcrun --find llvm-size 2>/dev/null || command -v llvm-size || true)
STATUS=0
for t in arm64-apple-ios15.0 aarch64-linux-android29; do
  out="$WORK/$t"; mkdir -p "$out"
  for f in "$HERE"/src/unishox.adb "$HERE"/src/unishox-tables.ads; do
    u=$(basename "$f" | sed 's/\.ad[bs]$//')
    (cd "$out" && "$AWP/bin/llvm-gcc" -c --target="$t" -gnateT="$WORK/lp64.atp" \
       --RTS="$AWP/lib/rts-native" -gnatec="$HERE/unishox.adc" \
       -O2 -gnatp -gnatn -gnat2022 -fPIC -I"$HERE/src" "$f" -o "$u.o")
  done
  undef=$("$NM" -u "$out"/*.o | grep -v ':$' | awk 'NF {print $NF}' | sort -u | tr '\n' ' ')
  bad=$(printf '%s\n' $undef | grep -v -E '^_?(memcpy|memset|bzero)$' || true)
  printf '== %s: %s\n   undefined: %s\n' "$t" "$(file "$out/unishox.o" | cut -d: -f2 | cut -c2-60)" "${undef:-none}"
  for o in "$out"/*.o; do
    sz=""; [ -n "$SIZE" ] && sz=$("$SIZE" "$o" | awk 'NR==2 {print "text " $1 ", "}')
    printf '   %-18s %sfile %s bytes\n' "$(basename "$o")" "$sz" "$(wc -c < "$o" | tr -d ' ')"
  done
  if [ -n "$bad" ]; then echo "   FAIL: unexpected undefined symbols: $bad"; STATUS=1; fi
done
exit $STATUS
