# Sourced by the scripts of this crate: puts the Alire GNAT and GPRbuild on PATH.
# Override with GNAT_BIN / GPR_BIN, or run inside `alr exec --`.
if [ -z "${GNAT_BIN:-}" ]; then
  GNAT_BIN=$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_native_*/bin 2>/dev/null | tail -1)
fi
if [ -z "${GPR_BIN:-}" ]; then
  GPR_BIN=$(ls -d "$HOME"/.local/share/alire/toolchains/gprbuild_*/bin 2>/dev/null | tail -1)
fi
PATH="${GNAT_BIN:+$GNAT_BIN:}${GPR_BIN:+$GPR_BIN:}$PATH"
export PATH GNAT_BIN GPR_BIN
if [ "$(uname -s)" = Darwin ] && [ -z "${SDKROOT:-}" ]; then
  SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true); export SDKROOT
fi
if [ "$(uname -s)" = Darwin ] && [ -n "${SDKROOT:-}" ]; then
  LIBRARY_PATH="$SDKROOT/usr/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"; export LIBRARY_PATH   # libSystem for the GNAT linker
fi
