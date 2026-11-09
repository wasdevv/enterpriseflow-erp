#!/usr/bin/env bash
# Compila as telas com a LCL do Lazarus para verificar formularios, DFMs e eventos sem Delphi.
# Uso: build-lcl.sh [nogui|gtk2]. "nogui" basta para checar tipos e nomes; "gtk2" gera binario grafico.
set -euo pipefail
source "$(dirname "$0")/fpc-env.sh"
WS="${1:-nogui}"
LAZ="${LAZARUS_DIR:-}"
if [ -z "$LAZ" ]; then
  for candidate in "$HOME"/.local/fpc/usr/lib/lazarus/* /usr/lib/lazarus/*; do
    [ -d "$candidate/lcl" ] && LAZ="$candidate" && break
  done
fi
OUT="$ROOT/build/lcl-$WS"
mkdir -p "$OUT"
PRESENTATION=()
while IFS= read -r dir; do PRESENTATION+=("-Fu$dir" "-Fi$dir"); done < <(find "$ROOT/src/presentation" -type d)
LIBS=()
[ -d "$HOME/.local/gtk2/link" ] && LIBS+=("-Fl$HOME/.local/gtk2/link")
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "${PRESENTATION[@]}" "${LIBS[@]}" -dLCL "-dLCL$WS" \
  "-Fu$LAZ/lcl/units/x86_64-linux/$WS" "-Fu$LAZ/lcl/units/x86_64-linux" \
  "-Fu$LAZ/components/lazutils/lib/x86_64-linux" "-Fu$LAZ/components/freetype/lib/x86_64-linux" \
  "-FU$OUT" "-FE$OUT" "$ROOT/tools/fpc/EnterpriseFlowLcl.lpr"
