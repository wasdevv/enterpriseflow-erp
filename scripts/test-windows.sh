#!/usr/bin/env bash
# A partir do WSL, roda os .exe de teste no Windows de verdade, contra o Firebird do WSL.
# Prova caminhos, processos, rede e cliente Firebird em Windows. Compilado com Free Pascal, nao Delphi.
set -euo pipefail
source "$(dirname "$0")/fpc-win64-env.sh"
BUILD_LOG="$WIN_BUILD/build.log"
"$ROOT/scripts/build-win64-tests.sh" > "$BUILD_LOG" 2>&1 || { grep -E 'Error|Fatal' "$BUILD_LOG"; echo "Compilacao falhou." >&2; exit 1; }

WIN_LOCAL="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' | tail -1)"
TARGET="$(wslpath "$WIN_LOCAL")/EnterpriseFlow-verificacao"
mkdir -p "$TARGET"

# Cliente oficial do Firebird para Windows, baixado uma vez.
if [ ! -f "$TARGET/fbclient.dll" ]; then
  WORK="$(mktemp -d)"
  curl -fsSL -o "$WORK/fb.zip" "https://github.com/FirebirdSQL/firebird/releases/download/v5.0.4/Firebird-5.0.4.1812-0-windows-x64.zip"
  python3 -I -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$WORK/fb.zip" "$WORK/fb"
  cp "$WORK"/fb/fbclient.dll "$WORK"/fb/firebird.msg "$WORK"/fb/msvcp140*.dll "$WORK"/fb/vcruntime140*.dll "$TARGET/"
  mkdir -p "$TARGET/plugins"
  cp "$WORK"/fb/plugins/chacha*.dll "$WORK"/fb/plugins/srp.dll "$TARGET/plugins/" 2>/dev/null || true
  rm -rf "$WORK"
fi
cp "$WIN_BUILD"/*.exe "$TARGET/"

export EF_TEST_DB_HOST="${EF_TEST_DB_HOST:-127.0.0.1}"
export EF_TEST_DB_PORT="${EF_TEST_DB_PORT:-53050}"
export EF_TEST_DB_USER="${EF_TEST_DB_USER:-SYSDBA}"
export EF_TEST_DB_PASSWORD="${EF_TEST_DB_PASSWORD:-masterkey}"
export EF_TEST_DB_PATH="${EF_TEST_DB_PATH:-$HOME/.local/share/enterpriseflow-fb/test-windows.fdb}"
export EF_TEST_API_PORT="${EF_TEST_API_PORT:-58768}"
export EF_TEST_API_URL="http://127.0.0.1:$EF_TEST_API_PORT"

# O banco fica no servidor do WSL; o efmigrate de Linux basta para criar.
"$ROOT/scripts/build-tests.sh" > "$BUILD/build.log" 2>&1 || { grep -E 'Error|Fatal' "$BUILD/build.log"; exit 1; }
rm -f "$EF_TEST_DB_PATH"
EF_DB_HOST="$EF_TEST_DB_HOST" EF_DB_PORT="$EF_TEST_DB_PORT" EF_DB_USER="$EF_TEST_DB_USER" EF_DB_PASSWORD="$EF_TEST_DB_PASSWORD" EF_DB_PATH="$EF_TEST_DB_PATH" EF_MIGRATIONS_DIR="$ROOT/database/migrations" \
  sh -c '"$0" create >/dev/null && "$0" migrate >/dev/null' "$BUILD/efmigrate"

python3 "$ROOT/tools/mock_fiscal_api.py" --port "$EF_TEST_API_PORT" &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null || true' EXIT
sleep 0.5

export WSLENV="EF_TEST_DB_HOST:EF_TEST_DB_PORT:EF_TEST_DB_USER:EF_TEST_DB_PASSWORD:EF_TEST_DB_PATH:EF_TEST_API_URL${WSLENV:+:$WSLENV}"
cd "$TARGET"
./EnterpriseFlowTests.exe "$@"
