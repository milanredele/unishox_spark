#!/bin/sh
# Cross-compile the library with GNAT-LLVM for the device targets, with the toolchain and
# light runtime of https://github.com/milanredele/ada-mobile: one compiler, --target=<triple>,
# the toolchain's LP64 target parameters (-gnateT), the light-runtime restrictions
# (unishox.adc), checks off (-gnatp, allowed because absence of run-time errors is proved).
# Then checks that the objects need nothing but memcpy/memset. On Apple targets LLVM's
# AArch64 back end lowers a memset of zeros with a variable size to bzero (libSystem),
# which is accepted as the same thing.
#
# Usage: ./build-target.sh [triple ...]
#   default: arm64-apple-macos15.0 arm64-apple-ios15.0 arm64-apple-ios15.0-simulator
#            aarch64-linux-android29
# Environment:
#   FC_TOOLS     ada-mobile's tool root (default ~/.local/share/freedomchat, as its toolchain/env.sh)
#   FC_GNATLLVM  GNAT-LLVM toolchain (default $FC_TOOLS/gnat-llvm, from ada-mobile's toolchain/install.sh)
#   FC_LP64_ATP  -gnateT file (default $FC_GNATLLVM/lib/lp64.atp, the installed toolchain/lp64.atp)
#   FC_RTS       runtime for --RTS (default $FC_TOOLS/rts/<triple>, from ada-mobile's runtime/build.sh,
#                when it exists; only its specs are read, nothing is linked)
#   FC_RTS_SHIM  =1: use the stand-in runtime instead (also used, with a note, when no light
#                runtime is installed): AdaWebPack's system.ads and GCC's ada.ads and interfac.ads
#                from the toolchain sources
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
FC_TOOLS=${FC_TOOLS:-$HOME/.local/share/freedomchat}
FC_GNATLLVM=${FC_GNATLLVM:-$FC_TOOLS/gnat-llvm}
FC_LP64_ATP=${FC_LP64_ATP:-$FC_GNATLLVM/lib/lp64.atp}
[ -x "$FC_GNATLLVM/bin/llvm-gcc" ] || { echo "GNAT-LLVM not found at $FC_GNATLLVM (run toolchain/install.sh)" >&2; exit 2; }
[ -f "$FC_LP64_ATP" ] || { echo "no target parameters $FC_LP64_ATP (run toolchain/install.sh)" >&2; exit 2; }
WORK="$HERE/build/target"
rm -rf "$WORK"; mkdir -p "$WORK"

NM=$(xcrun --find nm 2>/dev/null || command -v nm)
SIZE=$(xcrun --find llvm-size 2>/dev/null || command -v llvm-size || true)
STATUS=0
for t in ${*:-arm64-apple-macos15.0 arm64-apple-ios15.0 arm64-apple-ios15.0-simulator aarch64-linux-android29}; do
  out="$WORK/$t"; mkdir -p "$out"
  if [ -n "${FC_RTS:-}" ]; then rts=$FC_RTS
  elif [ "${FC_RTS_SHIM:-0}" != 1 ] && [ -d "$FC_TOOLS/rts/$t/adainclude" ]; then rts=$FC_TOOLS/rts/$t
  else
    [ "${FC_RTS_SHIM:-0}" = 1 ] || echo "note: no light runtime in $FC_TOOLS/rts/$t (runtime/build.sh $t makes it): using the stand-in" >&2
    rts="$WORK/stand-in-rts"
    if [ ! -d "$rts" ]; then
      G="$FC_GNATLLVM/src"; mkdir -p "$rts/adainclude" "$rts/adalib"
      cp "$G/adawebpack_src/source/rtl/system.ads" "$G/gnat_src/libgnat/ada.ads" \
         "$G/gnat_src/libgnat/interfac.ads" "$rts/adainclude/"
    fi
  fi
  for f in "$HERE"/src/unishox.adb "$HERE"/src/unishox-tables.ads; do
    u=$(basename "$f" | sed 's/\.ad[bs]$//')
    (cd "$out" && "$FC_GNATLLVM/bin/llvm-gcc" -c --target="$t" -gnateT="$FC_LP64_ATP" \
       --RTS="$rts" -gnatec="$HERE/unishox.adc" \
       -O2 -gnatp -gnatn -gnat2022 -fPIC -I"$HERE/src" "$f" -o "$u.o")
  done
  undef=$("$NM" -u "$out"/*.o | grep -v ':$' | awk 'NF {print $NF}' | sort -u | tr '\n' ' ')
  bad=$(printf '%s\n' $undef | grep -v -E '^_?(memcpy|memset|bzero)$' || true)
  printf '== %s: %s\n   runtime: %s\n   undefined: %s\n' "$t" "$(file "$out/unishox.o" | cut -d: -f2 | cut -c2-60)" "$rts" "${undef:-none}"
  for o in "$out"/*.o; do
    sz=""; [ -n "$SIZE" ] && sz=$("$SIZE" "$o" | awk 'NR==2 {print "text " $1 ", "}')
    printf '   %-18s %sfile %s bytes\n' "$(basename "$o")" "$sz" "$(wc -c < "$o" | tr -d ' ')"
  done
  if [ -n "$bad" ]; then echo "   FAIL: unexpected undefined symbols: $bad"; STATUS=1; fi
done
exit $STATUS
