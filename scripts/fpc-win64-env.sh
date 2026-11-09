#!/usr/bin/env bash
# Compilacao cruzada para Windows x64 com Free Pascal: gera .exe nativo sem precisar de Windows.
# Exige as units de Windows do FPC (pacotes fp-units-win-* no Debian/Ubuntu).
source "$(dirname "${BASH_SOURCE[0]}")/fpc-env.sh"
FPC_REAL="$(dirname "$(readlink -f "$FPC_BIN")")"
WIN_UNITS=""
for candidate in "$FPC_REAL/units/x86_64-win64" "/usr/lib/x86_64-linux-gnu/fpc/3.2.2/units/x86_64-win64"; do
  [ -d "$candidate" ] && WIN_UNITS="$candidate" && break
done
[ -n "$WIN_UNITS" ] || { echo "Units de Windows do FPC nao encontradas (fp-units-win-*)." >&2; exit 1; }
WIN_BUILD="$ROOT/build/win64"
mkdir -p "$WIN_BUILD"
SRC_WIN=()
while IFS= read -r dir; do SRC_WIN+=("-Fu$dir"); done < <(find "$ROOT/src" -type d -not -path '*/presentation*')
# fpcres embute os DFMs no executavel; com -n, o FPC nao o acha sozinho.
FPCRES_DIR="$(dirname "$(command -v fpcres || echo "$HOME/.local/fpc/bin/fpcres")")"
# -n ignora o fpc.cfg de Linux; os caminhos vao todos explicitos.
EF_WIN_FLAGS=(-n -Twin64 -Px86_64 -l- -vew "-FD$FPCRES_DIR" "-Fi$ROOT/src/shared" "${SRC_WIN[@]}" "-Fu$WIN_UNITS/*" "-FU$WIN_BUILD" "-FE$WIN_BUILD")
