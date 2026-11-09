#!/usr/bin/env bash
# Gera EnterpriseFlowTests.exe, race_worker.exe e efmigrate.exe para Windows x64.
set -euo pipefail
source "$(dirname "$0")/fpc-win64-env.sh"
"$FPC_BIN" "${EF_WIN_FLAGS[@]}" "-Fu$ROOT/tests/fpc-shim" "-Fu$ROOT/tests/unit" "-Fu$ROOT/tests/integration" "$ROOT/tests/EnterpriseFlowTests.dpr"
"$FPC_BIN" "${EF_WIN_FLAGS[@]}" "-Fu$ROOT/tests/integration" "$ROOT/tests/integration/race_worker.dpr"
"$FPC_BIN" "${EF_WIN_FLAGS[@]}" "$ROOT/tools/efmigrate.dpr"
ls -la "$WIN_BUILD"/*.exe
