#!/usr/bin/env bash
# Deixa pronto o que o programa precisa no WSL: Firebird, banco de demonstracao e servico simulado.
set -euo pipefail
source "$(dirname "$0")/fpc-env.sh"
export EF_TEST_DB_PORT="${EF_DB_PORT:-53050}" EF_TEST_DB_PASSWORD="${EF_DB_PASSWORD:-masterkey}"
"$ROOT/scripts/setup-firebird.sh" >/dev/null
export EF_DB_HOST=127.0.0.1 EF_DB_PORT="$EF_TEST_DB_PORT" EF_DB_USER=SYSDBA EF_DB_PASSWORD="$EF_TEST_DB_PASSWORD"
export EF_DB_PATH="${EF_DEMO_DB:-$HOME/.local/share/enterpriseflow-fb/demo.fdb}" EF_MIGRATIONS_DIR="$ROOT/database/migrations"
export LD_LIBRARY_PATH="${EF_FB_PREFIX:-$HOME/.local/firebird-5}/opt/firebird/lib:${LD_LIBRARY_PATH:-}"
[ -x "$BUILD/efmigrate" ] || "$FPC_BIN" "${EF_FPC_FLAGS[@]}" "$ROOT/tools/efmigrate.dpr" >/dev/null
if [ ! -f "$EF_DB_PATH" ]; then
  "$BUILD/efmigrate" create >/dev/null
  "$BUILD/efmigrate" migrate >/dev/null
  "$BUILD/efmigrate" seed "$ROOT/database/seeds/001_demo.sql" >/dev/null
else
  "$BUILD/efmigrate" migrate >/dev/null
fi
if ! (exec 3<>/dev/tcp/127.0.0.1/8765) 2>/dev/null; then
  nohup python3 "$ROOT/tools/mock_fiscal_api.py" --port 8765 >/dev/null 2>&1 &
fi
echo "Pronto. Banco: $EF_DB_PATH"
