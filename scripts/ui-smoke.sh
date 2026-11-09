#!/usr/bin/env bash
# Roda o roteiro de telas (LCL em Xvfb) num banco de demonstracao recem-criado.
# Argumento opcional: diretorio para salvar capturas de tela.
set -euo pipefail
source "$(dirname "$0")/fpc-env.sh"
LAZ="${LAZARUS_DIR:-}"
if [ -z "$LAZ" ]; then
  for candidate in "$HOME"/.local/fpc/usr/lib/lazarus/* /usr/lib/lazarus/*; do
    [ -d "$candidate/lcl" ] && LAZ="$candidate" && break
  done
fi
OUT="$ROOT/build/lcl-gtk2"
mkdir -p "$OUT"
PRESENTATION=()
while IFS= read -r dir; do PRESENTATION+=("-Fu$dir" "-Fi$dir"); done < <(find "$ROOT/src/presentation" -type d)
LIBS=()
if [ -d "$HOME/.local/gtk2/link" ]; then
  LIBS+=("-Fl$HOME/.local/gtk2/link")
  export LD_LIBRARY_PATH="$HOME/.local/gtk2/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
fi
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "${PRESENTATION[@]}" "${LIBS[@]}" -dLCL -dLCLgtk2 \
  "-Fu$LAZ/lcl/units/x86_64-linux/gtk2" "-Fu$LAZ/lcl/units/x86_64-linux" \
  "-Fu$LAZ/components/lazutils/lib/x86_64-linux" "-Fu$LAZ/components/freetype/lib/x86_64-linux" \
  "-FU$OUT" "-FE$OUT" "$ROOT/tests/ui/UiSmoke.lpr" > "$OUT/build.log" 2>&1 || { grep -E 'Error|Fatal' "$OUT/build.log"; exit 1; }
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "$ROOT/tools/efmigrate.dpr" > "$BUILD/efmigrate.log" 2>&1 || { grep -E 'Error|Fatal' "$BUILD/efmigrate.log"; exit 1; }

export EF_DB_HOST="${EF_DB_HOST:-127.0.0.1}" EF_DB_PORT="${EF_DB_PORT:-53050}" EF_DB_USER="${EF_DB_USER:-SYSDBA}"
export EF_DB_PASSWORD="${EF_DB_PASSWORD:-masterkey}" EF_DB_PATH="${EF_DB_PATH:-$HOME/.local/share/enterpriseflow-fb/ui.fdb}"
export EF_MIGRATIONS_DIR="$ROOT/database/migrations" EF_LOG_PATH="$OUT/ui.log"
API_PORT="${EF_UI_API_PORT:-58767}"
export EF_API_URL="http://127.0.0.1:$API_PORT"
[ -n "${1:-}" ] && export EF_UI_SHOTS="$1"
rm -f "$EF_DB_PATH"
"$BUILD/efmigrate" create >/dev/null
"$BUILD/efmigrate" migrate >/dev/null
"$BUILD/efmigrate" seed "$ROOT/database/seeds/001_demo.sql" >/dev/null
python3 "$ROOT/tools/mock_fiscal_api.py" --port "$API_PORT" &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null || true' EXIT
sleep 0.5
GTK_MODULES= xvfb-run -a -s "-screen 0 1280x800x24" "$OUT/UiSmoke"
