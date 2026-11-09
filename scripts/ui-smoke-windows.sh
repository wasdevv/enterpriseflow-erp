#!/usr/bin/env bash
# A partir do WSL, roda o roteiro de telas no Windows de verdade, com controles nativos Win32 e
# numa area de trabalho oculta. Argumento opcional: pasta (no WSL) para as capturas de tela.
set -euo pipefail
source "$(dirname "$0")/fpc-win64-env.sh"
EF_WIN_SUBSYSTEM=-WC "$ROOT/scripts/build-win64-lcl.sh" "$ROOT/tests/ui/UiSmoke.lpr" "$ROOT/tests/ui/BootSmoke.lpr" > "$WIN_BUILD/ui-build.log" 2>&1 || { grep -E 'Error|Fatal' "$WIN_BUILD/ui-build.log"; exit 1; }
"$FPC_BIN" "${EF_WIN_FLAGS[@]}" "$ROOT/tests/ui/RunHidden.lpr" > "$WIN_BUILD/hidden-build.log" 2>&1 || { grep -E 'Error|Fatal' "$WIN_BUILD/hidden-build.log"; exit 1; }
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "$ROOT/tools/efmigrate.dpr" > "$BUILD/efmigrate.log" 2>&1 || { grep -E 'Error|Fatal' "$BUILD/efmigrate.log"; exit 1; }

WIN_LOCAL="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' | tail -1)"
TARGET="$(wslpath "$WIN_LOCAL")/EnterpriseFlow-verificacao"
[ -f "$TARGET/fbclient.dll" ] || { echo "Rode scripts/test-windows.sh antes: ele baixa o cliente Firebird." >&2; exit 1; }
cp "$WIN_BUILD/UiSmoke.exe" "$WIN_BUILD/BootSmoke.exe" "$WIN_BUILD/RunHidden.exe" "$TARGET/"

export EF_DB_HOST="${EF_DB_HOST:-127.0.0.1}" EF_DB_PORT="${EF_DB_PORT:-53050}" EF_DB_USER="${EF_DB_USER:-SYSDBA}"
export EF_DB_PASSWORD="${EF_DB_PASSWORD:-masterkey}" EF_DB_PATH="${EF_DB_PATH:-$HOME/.local/share/enterpriseflow-fb/ui-windows.fdb}"
export EF_MIGRATIONS_DIR="$ROOT/database/migrations" EF_LOG_PATH="ui-smoke.log"
API_PORT="${EF_UI_API_PORT:-58769}"
export EF_API_URL="http://127.0.0.1:$API_PORT"
rm -f "$EF_DB_PATH"
"$BUILD/efmigrate" create >/dev/null
"$BUILD/efmigrate" migrate >/dev/null
"$BUILD/efmigrate" seed "$ROOT/database/seeds/001_demo.sql" >/dev/null
python3 "$ROOT/tools/mock_fiscal_api.py" --port "$API_PORT" &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null || true' EXIT
sleep 0.5

export EF_UI_SHOTS="capturas"
export WSLENV="EF_DB_HOST:EF_DB_PORT:EF_DB_USER:EF_DB_PASSWORD:EF_DB_PATH:EF_API_URL:EF_LOG_PATH:EF_UI_SHOTS${WSLENV:+:$WSLENV}"
rm -rf "$TARGET/capturas"
cd "$TARGET"
STATUS=0
./RunHidden.exe "$(wslpath -w "$TARGET/UiSmoke.exe")" || STATUS=$?

# Caminho do executavel final, lendo a configuracao de um ini ao lado dele e nao do ambiente.
cat > "$TARGET/enterpriseflow.ini" <<INI
[database]
host=$EF_DB_HOST
port=$EF_DB_PORT
path=$EF_DB_PATH
user=$EF_DB_USER
password=$EF_DB_PASSWORD
[integration]
base_url=$EF_API_URL
[logging]
path=boot-smoke.log
INI
env -u EF_DB_HOST -u EF_DB_PORT -u EF_DB_USER -u EF_DB_PASSWORD -u EF_DB_PATH -u EF_API_URL -u EF_LOG_PATH -u EF_UI_SHOTS WSLENV= \
  ./RunHidden.exe "$(wslpath -w "$TARGET/BootSmoke.exe")" || STATUS=$?
rm -f "$TARGET/enterpriseflow.ini"
if [ -n "${1:-}" ]; then
  mkdir -p "$1"
  cp -r "$TARGET"/capturas/. "$1/" 2>/dev/null || true
fi
exit "$STATUS"
