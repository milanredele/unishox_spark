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
