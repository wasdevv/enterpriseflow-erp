#!/usr/bin/env bash
# Recria um banco de teste isolado, aplica as migrations, sobe o servico simulado e roda a
# suite. Requer um Firebird 5 acessivel. Variaveis: EF_TEST_DB_HOST/PORT/USER/PASSWORD/PATH.
set -euo pipefail
source "$(dirname "$0")/fpc-env.sh"
"$ROOT/scripts/build-tests.sh" 2>&1 | grep -vE 'crt|Note:|APPTYPE|managed type|Warning: Local' || true
export EF_TEST_DB_HOST="${EF_TEST_DB_HOST:-127.0.0.1}"
export EF_TEST_DB_PORT="${EF_TEST_DB_PORT:-53050}"
export EF_TEST_DB_USER="${EF_TEST_DB_USER:-SYSDBA}"
export EF_TEST_DB_PASSWORD="${EF_TEST_DB_PASSWORD:-masterkey}"
export EF_TEST_DB_PATH="${EF_TEST_DB_PATH:-$HOME/.local/share/enterpriseflow-fb/test.fdb}"
export EF_TEST_API_PORT="${EF_TEST_API_PORT:-58765}"
export EF_TEST_API_URL="http://127.0.0.1:$EF_TEST_API_PORT"
rm -f "$EF_TEST_DB_PATH"
export EF_DB_HOST="$EF_TEST_DB_HOST" EF_DB_PORT="$EF_TEST_DB_PORT" EF_DB_USER="$EF_TEST_DB_USER" EF_DB_PASSWORD="$EF_TEST_DB_PASSWORD" EF_DB_PATH="$EF_TEST_DB_PATH"
export EF_MIGRATIONS_DIR="$ROOT/database/migrations"
"$BUILD/efmigrate" create
"$BUILD/efmigrate" migrate
python3 "$ROOT/tools/mock_fiscal_api.py" --port "$EF_TEST_API_PORT" &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  python3 - "$EF_TEST_API_URL" 2>/dev/null <<'PY' && break || sleep 0.1
import sys, urllib.request
urllib.request.urlopen(sys.argv[1] + "/health", timeout=1)
PY
done
"$BUILD/EnterpriseFlowTests" "$@"
