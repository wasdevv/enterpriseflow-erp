#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/fpc-env.sh"
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "-Fu$ROOT/tests/fpc-shim" "-Fu$ROOT/tests/unit" "-Fu$ROOT/tests/integration" "$ROOT/tests/EnterpriseFlowTests.dpr"
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "$ROOT/tools/efmigrate.dpr"
"$FPC_BIN" "${EF_FPC_FLAGS[@]}" "-Fu$ROOT/tests/integration" "$ROOT/tests/integration/race_worker.dpr"
