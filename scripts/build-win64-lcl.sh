#!/usr/bin/env bash
# Compila as telas para Windows x64 com a LCL (widgetset Win32, os mesmos controles nativos da
# VCL). Exige as fontes do Lazarus (pacote lazarus-src). Nao substitui compilar em Delphi.
# Uso: build-win64-lcl.sh <programa.lpr> ...
set -euo pipefail
source "$(dirname "$0")/fpc-win64-env.sh"
LAZ_SRC="${LAZARUS_SRC:-}"
if [ -z "$LAZ_SRC" ]; then
  WIN32_DIR="$(find "$HOME/.local/lazarus-src" /usr/share/lazarus /usr/lib/lazarus -type d -path '*lcl/interfaces/win32' 2>/dev/null | head -1 || true)"
  [ -n "$WIN32_DIR" ] || { echo "Fontes do Lazarus nao encontradas (lazarus-src)." >&2; exit 1; }
  LAZ_SRC="${WIN32_DIR%/lcl/interfaces/win32}"
fi
LCL_OUT="$WIN_BUILD/lcl"
mkdir -p "$LCL_OUT"
UI_PATHS=()
while IFS= read -r dir; do UI_PATHS+=("-Fu$dir" "-Fi$dir"); done < <(find "$ROOT/src/presentation" -type d)
LCL_PATHS=(
  "-Fu$LAZ_SRC/lcl" "-Fu$LAZ_SRC/lcl/forms" "-Fu$LAZ_SRC/lcl/widgetset"
  "-Fu$LAZ_SRC/lcl/interfaces/win32" "-Fu$LAZ_SRC/components/lazutils" "-Fu$LAZ_SRC/components/freetype"
  "-Fi$LAZ_SRC/lcl/include" "-Fi$LAZ_SRC/lcl/interfaces/win32" "-Fi$LAZ_SRC/components/lazutils"
)
for program in "$@"; do
  "$FPC_BIN" "${EF_WIN_FLAGS[@]}" "${UI_PATHS[@]}" "${LCL_PATHS[@]}" -MObjFPC -Scghi -dLCL -dLCLwin32 "${EF_WIN_SUBSYSTEM:--WG}" "-FU$LCL_OUT" "-FE$WIN_BUILD" "$program"
done
