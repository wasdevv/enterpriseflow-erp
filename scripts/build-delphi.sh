#!/usr/bin/env bash
# A partir do WSL: copia o projeto para uma pasta do Windows (o msbuild nao aceita caminho UNC) e
# chama scripts/windows/build-delphi.ps1. Argumentos vao direto para o script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIN_LOCAL="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' | tail -1)"
TARGET="$(wslpath "$WIN_LOCAL")/EnterpriseFlow-delphi"
rm -rf "$TARGET/src" "$TARGET/tests" "$TARGET/tools"
mkdir -p "$TARGET"
tar -C "$ROOT" --exclude=build --exclude=.git -cf - . | tar -C "$TARGET" -xf -
cd "$TARGET"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$TARGET/scripts/windows/build-delphi.ps1")" "$@"
