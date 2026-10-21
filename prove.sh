#!/bin/sh
# Copyright 2026 The FreedomChat authors
# SPDX-License-Identifier: Apache-2.0
#
# GNATprove on Unishox (unishox_spark.gpr, release mode), through the shared ../tools/prove.sh:
# every check proved, no warning, the margin to the limits kept (../core/proof/README.md).
# gnatprove is taken from $GNATPROVE, then PATH, then the Alire cache
# (`alr get gnatprove` or `alr with gnatprove` puts it there).
# Usage: ./prove.sh [extra gnatprove switches], e.g. ./prove.sh --info
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
# Checks of 16 VCs or more: 7 today (2026-10-21), all in Try_Template (unishox.adb:606-622,
# an unrolled loop over Template_Index); a new one is most likely a loop without an invariant.
FC_PROOF_MAX_WIDE=${FC_PROOF_MAX_WIDE:-7}
export FC_PROOF_MAX_WIDE
exec sh "$HERE/../tools/prove.sh" "$HERE/unishox_spark.gpr" -XUNISHOX_BUILD_MODE=release "$@"
