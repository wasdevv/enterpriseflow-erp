#!/usr/bin/env bash
# Localiza o compilador. Use FPC_BIN/PPC_CONFIG_PATH para apontar outro; sem isso, tenta
# a instalacao em ~/.local e depois o PATH.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${FPC_BIN:-}" ]; then
  if [ -x "$HOME/.local/fpc/bin/fpc" ]; then
    FPC_BIN="$HOME/.local/fpc/bin/fpc"
    export PPC_CONFIG_PATH="$HOME/.local/fpc"
    export LD_LIBRARY_PATH="$HOME/.local/firebird-5/opt/firebird/lib:${LD_LIBRARY_PATH:-}"
  else
    FPC_BIN="$(command -v fpc)"
  fi
fi
SRC_PATHS=()
while IFS= read -r dir; do SRC_PATHS+=("-Fu$dir"); done < <(find "$ROOT/src" -type d -not -path '*/presentation*')
BUILD="$ROOT/build/fpc"
mkdir -p "$BUILD"
EF_FPC_FLAGS=(-l- -vew -Sew- "-Fi$ROOT/src/shared" "${SRC_PATHS[@]}" "-FU$BUILD" "-FE$BUILD" -gl)
