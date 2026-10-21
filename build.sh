#!/bin/sh
# Build the library with the native Alire GNAT.
# Usage: ./build.sh [release|debug|checks]   (default: release)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
gprbuild -q -p -P "$HERE/unishox_spark.gpr" -XUNISHOX_BUILD_MODE="${1:-release}"
