#!/bin/sh
# Copyright 2026 The FreedomChat authors
# SPDX-License-Identifier: Apache-2.0
# Differential test of the cross-compiled library on the device targets. LOCAL ONLY: it needs
# the GNAT-LLVM toolchain and light runtimes of https://github.com/milanredele/ada-mobile, Xcode,
# the Android NDK, an iOS simulator and an Android emulator or device (the CI has none).
# For each triple: compiles src/unishox.adb and src/unishox-tables.ads exactly as
# build-target.sh does (llvm-gcc --target, -gnateT lp64.atp, --RTS light runtime, unishox.adc,
# -O2 -gnatp -gnatn -fPIC), with the C interface tests/cross/unishox_c.adb; compiles
# reference/unishox2.c (-fwrapv -DUNISHOX_API_WITH_OUTPUT_LEN=1), tests/c/ref_wrap.c and the
# driver tests/cross/cross_test.c with the target's C compiler; links and runs the driver:
#   arm64-apple-macos15.0          on the host
#   arm64-apple-ios15.0-simulator  on a booted iOS simulator (xcrun simctl spawn)
#   aarch64-linux-android29        on the online Android emulator or device (adb)
#   arm64-apple-ios15.0            linked only (no device)
# The driver runs the corpus, N random round trips and N decoder fuzz cases (fixed seed)
# with the checks of tests/src/diff_check.adb, and prints a digest of every Ada output: the
# outputs of all targets that ran must be identical. Prints one result line per target; exits 1 if
# a target failed to build or failed a check, else 2 if a target could not be run, else 0.
# Usage: tests/run-target.sh [triple ...]   (default: the four above)
# Environment: FC_TOOLS, FC_GNATLLVM, FC_LP64_ATP, FC_RTS as build-target.sh (the light runtime
#   is required here: the C interface uses Interfaces.C); and
#   N_RANDOM, N_FUZZ  round trips and fuzz cases per target (default 100000 each; about 12 s per target)
#   NDK               Android NDK (default /opt/homebrew/share/android-commandlinetools/ndk/27.2.12479018)
#   ANDROID_HOME      Android SDK, for adb (default /opt/homebrew/share/android-commandlinetools)
#   ANDROID_SERIAL    adb device (default: the only one online); no emulator is started
#   SIM_UDID          simulator (default: the first booted one); booted if it is not
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
FC_TOOLS=${FC_TOOLS:-$HOME/.local/share/freedomchat}
FC_GNATLLVM=${FC_GNATLLVM:-$FC_TOOLS/gnat-llvm}
FC_LP64_ATP=${FC_LP64_ATP:-$FC_GNATLLVM/lib/lp64.atp}
NDK=${NDK:-/opt/homebrew/share/android-commandlinetools/ndk/27.2.12479018}
ANDROID_HOME=${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}
ADB=$ANDROID_HOME/platform-tools/adb
N_RANDOM=${N_RANDOM:-100000}
N_FUZZ=${N_FUZZ:-100000}
[ -x "$FC_GNATLLVM/bin/llvm-gcc" ] || { echo "GNAT-LLVM not found at $FC_GNATLLVM (ada-mobile's toolchain/install.sh); this test runs locally only" >&2; exit 2; }
[ -f "$FC_LP64_ATP" ] || { echo "no target parameters $FC_LP64_ATP (ada-mobile's toolchain/install.sh)" >&2; exit 2; }
WORK="$HERE/build/target"
mkdir -p "$WORK"
CORPUS="$HERE/corpus.txt"

# build <triple>: objects and the cross_test program in $out; sets RESULT on failure
build() {
  case $1 in
    arm64-apple-macos*)         CC="xcrun --sdk macosx clang -target $1" ;;
    arm64-apple-ios*-simulator) CC="xcrun --sdk iphonesimulator clang -target $1 -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path)" ;;
    arm64-apple-ios*)           CC="xcrun --sdk iphoneos clang -target $1 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)" ;;
    aarch64-linux-android*)
      ndkcc=$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin/clang 2>/dev/null | head -1)
      [ -n "$ndkcc" ] || { RESULT="NOT RUN: no Android NDK at $NDK"; return 1; }
      CC="$ndkcc --target=$1" ;;
    *) RESULT="NOT RUN: unknown target"; return 1 ;;
  esac
  rts=${FC_RTS:-$FC_TOOLS/rts/$1}
  [ -d "$rts/adainclude" ] || { RESULT="NOT RUN: no light runtime in $rts (ada-mobile's runtime/build.sh $1)"; return 1; }
  for f in "$ROOT/src/unishox.adb" "$ROOT/src/unishox-tables.ads" "$HERE/cross/unishox_c.adb"; do
    u=$(basename "$f" | sed 's/\.ad[bs]$//')
    (cd "$out" && "$FC_GNATLLVM/bin/llvm-gcc" -c --target="$1" -gnateT="$FC_LP64_ATP" \
       --RTS="$rts" -gnatec="$ROOT/unishox.adc" \
       -O2 -gnatp -gnatn -gnat2022 -fPIC -I"$ROOT/src" -I"$HERE/cross" "$f" -o "$u.o") \
      >> "$out/build.log" 2>&1 || { RESULT="BUILD FAILED (Ada, see $out/build.log)"; return 1; }
  done
  { $CC -O2 -fwrapv -w -DUNISHOX_API_WITH_OUTPUT_LEN=1 -I"$ROOT/reference" \
      -c "$ROOT/reference/unishox2.c" -o "$out/unishox2.o" &&
    $CC -O2 -Wall -DUNISHOX_API_WITH_OUTPUT_LEN=1 -I"$ROOT/reference" \
      -c "$HERE/c/ref_wrap.c" -o "$out/ref_wrap.o" &&
    $CC -O2 -Wall -c "$HERE/cross/cross_test.c" -o "$out/cross_test.o" &&
    $CC -o "$out/cross_test" "$out/cross_test.o" "$out/unishox_c.o" "$out/unishox.o" \
      "$out/unishox-tables.o" "$out/unishox2.o" "$out/ref_wrap.o"
  } >> "$out/build.log" 2>&1 || { RESULT="BUILD FAILED (C or link, see $out/build.log)"; return 1; }
}

run_sim() {
  udid=${SIM_UDID:-$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)}
  [ -n "$udid" ] || { RESULT="NOT RUN: no booted simulator (set SIM_UDID)"; return 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" > /dev/null 2>&1 || { RESULT="NOT RUN: simulator $udid does not boot"; return 1; }
  xcrun simctl spawn "$udid" "$out/cross_test" "$CORPUS" "$N_RANDOM" "$N_FUZZ" > "$out/run.log" 2>&1 \
    || echo "exit status $?" >> "$out/run.log"
  NOTE="simulator $udid"
}

run_android() {
  [ -x "$ADB" ] || { RESULT="NOT RUN: no adb at $ADB"; return 1; }
  "$ADB" get-state > /dev/null 2>&1 || { RESULT="NOT RUN: no Android device online (no emulator is started)"; return 1; }
  dir=/data/local/tmp/unishox_spark
  "$ADB" shell "mkdir -p $dir" > /dev/null
  "$ADB" push "$out/cross_test" "$CORPUS" "$dir/" > /dev/null 2>&1 || { RESULT="NOT RUN: adb push failed"; return 1; }
  "$ADB" shell "chmod +x $dir/cross_test; $dir/cross_test $dir/corpus.txt $N_RANDOM $N_FUZZ; echo exit status \$?" \
    | tr -d '\r' > "$out/run.log" 2>&1
  sed -i '' '/^exit status 0$/d' "$out/run.log"
  NOTE="Android $("$ADB" shell getprop ro.build.version.release | tr -d '\r') $("$ADB" shell getprop ro.product.cpu.abi | tr -d '\r')"
}

STATUS=0
FIRST=
for t in ${*:-arm64-apple-macos15.0 arm64-apple-ios15.0-simulator aarch64-linux-android29 arm64-apple-ios15.0}; do
  out="$WORK/$t"; rm -rf "$out"; mkdir -p "$out"
  RESULT=; NOTE=
  start=$(date +%s)
  if build "$t"; then
    case $t in
      arm64-apple-macos*)
        "$out/cross_test" "$CORPUS" "$N_RANDOM" "$N_FUZZ" > "$out/run.log" 2>&1 \
          || echo "exit status $?" >> "$out/run.log"
        NOTE="host macOS $(sw_vers -productVersion)" ;;
      arm64-apple-ios*-simulator) run_sim || true ;;
      aarch64-linux-android*)     run_android || true ;;
      arm64-apple-ios*)           RESULT="linked only (no device)" ;;
    esac
    if [ -z "$RESULT" ]; then
      if grep -q '^PASS$' "$out/run.log" && ! grep -q '^exit status' "$out/run.log"; then
        RESULT="PASS: $(grep '^checks:' "$out/run.log")"
        if [ -z "$FIRST" ]; then FIRST=$t
        elif ! cmp -s "$WORK/$FIRST/run.log" "$out/run.log"; then
          RESULT="FAIL: output differs from $FIRST's"; diff "$WORK/$FIRST/run.log" "$out/run.log" || true
        fi
      else
        RESULT="FAIL (see $out/run.log)"; sed -n '1,25p' "$out/run.log" | grep -v '^  sample'
      fi
    fi
  fi
  case $RESULT in
    FAIL*|BUILD*) STATUS=1 ;;
    NOT\ RUN*) [ $STATUS = 1 ] || STATUS=2 ;;
  esac
  printf '%-30s %s%s, %ss\n' "$t" "$RESULT" "${NOTE:+ [$NOTE]}" "$(( $(date +%s) - start ))"
done
exit $STATUS
