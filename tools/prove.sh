#!/bin/sh
# Copyright 2026 FreedomChat contributors
# SPDX-License-Identifier: Apache-2.0
#
# GNATprove on one crate (flow analysis, absence of run-time errors and
# the contracts). Fails unless every check is proved, no warning is
# reported and every proved check keeps its margin to the limits. The
# crate calls it through its wrapper, ./prove.sh (unishox_spark.gpr). The
# practice comes from the FreedomChat core (core/proof/README.md there),
# where it is shared with the fc_core crate.
#
# Usage: tools/prove.sh <gpr> [-X...] [extra gnatprove switches]
# e.g. ./prove.sh --report=all to list every proved check,
#      ./prove.sh -u unishox.adb for one unit during development,
#      ./prove.sh --info to list the loops gnatprove unrolls.
#
#   GNATPROVE=<path>/bin/gnatprove   default: gnatprove on PATH, else a copy
#                                    fetched with `alr get gnatprove` (Alire's
#                                    release directories) or `alr install`.
#
# The switches of package Prove of the gpr apply: --mode=all --level=2,
# CVC5 and Z3 with a limit in steps (--steps=100000, --timeout=60 as a
# backstop), --checks-as-errors=on (an unproved check fails the run),
# --report=statistics (the steps and time of every proved check, for the
# margin), -j0, and gnatprove's file cache of proof results.
#
# The cache: --memcached-server=file:$FC_PROOF_CACHE (default
# ~/.local/share/unishox_spark/proof-cache, created here) is shared by every
# worktree and branch on the machine, keyed by the hash of each
# verification condition, so a fresh worktree re-proves only what changed.
# A merge is verified by the full run, not by gnatprove's --replay: a
# condition found in the cache never reaches why3, so the sessions under
# obj/*/gnatprove keep the goals of the last real prover run and a replay
# reports the current checks unproved.
#
# One proof at a time on the machine: a run takes every core, and two at
# once only slow each other down. A second run waits for the first (the
# lock is a directory in the cache; FC_PROVE_NOLOCK=1 skips it).
#
# The margin: a check proved with more than FC_PROOF_MAX_STEPS (default
# 60000) steps or FC_PROOF_MAX_SECONDS (default 20) seconds fails the run
# although it is proved ("too close to the limit"): it would not stay
# proved when the code around it changes. Make that proof easier (an
# assertion, a lemma, a smaller subprogram); do not raise the limit.
#
# Wide checks: a loop without a loop invariant of at most 20 iterations
# (by its bounds, or by the range of their types) is unrolled by
# gnatprove, every check of its body proved once per iteration and path.
# The run counts the checks of 16 VCs or more and fails when there are
# more than FC_PROOF_MAX_WIDE (the wrapper of each crate sets today's
# count); a new one is most likely a loop that needs an invariant. With
# --info the run also counts the loops gnatprove unrolls ("unrolling
# loop").
#
# No warnings: a "warning:" line of gnatprove or of the compiler fails the
# run (gnatprove runs with --warnings=continue so that all are listed).
# Remove the warning at its cause; pragma Warnings (Off) only when the
# warning is wrong, with the reason next to it.
#
# Only what is not an info line is shown, then the summary table and the
# margin; the full output is obj/prove.log next to the gpr.

set -eu

if [ $# -lt 1 ]; then
   echo "usage: tools/prove.sh <gpr> [-X...] [extra gnatprove switches]" >&2
   exit 2
fi
gpr=$1; shift
gpr_dir=$(cd "$(dirname "$gpr")" && pwd)
gpr=$gpr_dir/$(basename "$gpr")
[ -f "$gpr" ] || { echo "prove.sh: no project $gpr" >&2; exit 2; }

cache=${FC_PROOF_CACHE:-$HOME/.local/share/unishox_spark/proof-cache}
mkdir -p "$cache"
FC_PROOF_CACHE=$cache
export FC_PROOF_CACHE

gnatprove=${GNATPROVE:-$(command -v gnatprove 2>/dev/null || true)}
if [ -z "$gnatprove" ]; then
   gnatprove=$(ls -d "$HOME"/.local/share/alire/releases/gnatprove_*/bin/gnatprove \
                     "$HOME"/.cache/alire/releases/gnatprove_*/bin/gnatprove \
                     "$HOME"/.alire/bin/gnatprove 2>/dev/null | tail -1 || true)
fi
if [ -z "$gnatprove" ] || ! command -v "$gnatprove" >/dev/null 2>&1; then
   echo "prove.sh: gnatprove not found: set GNATPROVE, or run 'alr get gnatprove' and put its bin/ on PATH" >&2
   exit 2
fi

lock=$cache/.prove.lock
if [ -z "${FC_PROVE_NOLOCK:-}" ]; then
   said=
   while ! mkdir "$lock" 2>/dev/null; do
      holder=$(cat "$lock/pid" 2>/dev/null || true)
      if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
         rm -rf "$lock"   # the holder is gone
         continue
      fi
      if [ -z "$said" ]; then
         echo "prove.sh: waiting for the proof of process ${holder:-?}" >&2
         said=1
      fi
      sleep 5
   done
   echo $$ > "$lock/pid"
   trap 'rm -rf "$lock"' EXIT
   trap 'exit 130' INT TERM
fi

echo "prove.sh: $(basename "$gpr") with $("$gnatprove" --version | head -1)"
mkdir -p "$gpr_dir/obj"
log=$gpr_dir/obj/prove.log
status=0
"$gnatprove" -P "$gpr" "$@" > "$log" 2>&1 || status=$?
# an info message and its continuation lines (indented) are not shown
awk '/: info: / { info = 1; next }
     info && /^ / { next }
     { info = 0 }
     !/^Summary logged in / { print }' "$log"

summary=$(sed -n 's/^Summary logged in //p' "$log" | tail -1)
if [ -n "$summary" ] && [ -f "$summary" ]; then
   sed -n '/^Summary of SPARK analysis/,/^Total/p' "$summary"
fi

max_steps=${FC_PROOF_MAX_STEPS:-60000}
max_seconds=${FC_PROOF_MAX_SECONDS:-20}
max_wide=${FC_PROOF_MAX_WIDE:-0}
awk -v max_steps="$max_steps" -v max_seconds="$max_seconds" \
    -v max_wide="$max_wide" '
   / info: unrolling loop/ || /^  unrolling loop/ { unrolled++ }
   /warning:/ { warnings++ }
   / info: .* proved \(/ {
      where = $1
      line = $0
      top_s = 0; top_t = 0
      while (match(line, /in max [0-9.]+ seconds and [0-9]+ step/)) {
         part = substr(line, RSTART, RLENGTH)
         split(part, w, " ")
         if (w[3] + 0 > top_t) top_t = w[3] + 0
         if (w[6] + 0 > top_s) top_s = w[6] + 0
         line = substr(line, RSTART + RLENGTH)
      }
      vcs = 0   # the VCs of the check, over the provers
      line = $0
      while (match(line, /[0-9]+ VC/)) {
         vcs += substr(line, RSTART, RLENGTH - 3)
         line = substr(line, RSTART + RLENGTH)
      }
      if (vcs >= 16) wide++
      if (vcs > best_v) { best_v = vcs; best_v_at = where }
      n++
      if (top_s > best_s) { best_s = top_s; best_s_at = where }
      if (top_t > best_t) { best_t = top_t; best_t_at = where }
      if (top_s > max_steps || top_t > max_seconds) {
         printf "prove.sh: too close to the limit: %s %d steps, %.1f s\n",
                where, top_s, top_t
         bad++
      }
   }
   END {
      if (n == 0) {
         print "prove.sh: proof margin: no statistics in this run"
      } else {
         printf "prove.sh: proof margin: %d checks proved here, at most %d of 100000 steps (%s), %.1f of 60 s (%s)\n",
                n, best_s, best_s_at, best_t, best_t_at
         printf "prove.sh: checks of 16 VCs or more: %d of at most %d, the largest %d VCs (%s)\n",
                wide, max_wide, best_v, best_v_at
         if (wide > max_wide) {
            print "prove.sh: too many checks of 16 VCs or more: a loop without an invariant? (prove.sh --info)"
            bad++
         }
      }
      if (unrolled > 0)
         printf "prove.sh: loops unrolled: %d\n", unrolled
      if (warnings > 0) {
         printf "prove.sh: %d warning lines (shown above; none allowed)\n",
                warnings
         bad++
      }
      exit (bad > 0) ? 1 : 0
   }' "$log" || { [ "$status" -ne 0 ] || status=1; }
if [ "$status" -eq 0 ]; then
   echo "prove.sh: all checks proved (log $log)"
else
   echo "prove.sh: FAILED (log $log)"
fi
exit $status
