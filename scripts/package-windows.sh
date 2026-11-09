#!/usr/bin/env bash
# Monta uma pasta com o programa para abrir no Windows. Compilado com Free Pascal e LCL, sem Delphi:
# serve para usar e demonstrar o sistema, nao para afirmar que ele roda em Delphi.
# Uso: package-windows.sh [pasta no WSL]. Padrao: Downloads do usuario do Windows.
set -euo pipefail
source "$(dirname "$0")/fpc-win64-env.sh"
"$ROOT/scripts/build-win64-lcl.sh" "$ROOT/tools/fpc/EnterpriseFlowLcl.lpr" > "$WIN_BUILD/app-build.log" 2>&1 || { grep -E 'Error|Fatal' "$WIN_BUILD/app-build.log"; exit 1; }
WIN_LOCAL="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' | tail -1)"
CLIENT="$(wslpath "$WIN_LOCAL")/EnterpriseFlow-verificacao"
[ -f "$CLIENT/fbclient.dll" ] || { echo "Rode scripts/test-windows.sh antes: ele baixa o cliente Firebird." >&2; exit 1; }
WIN_HOME="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' | tail -1)"
TARGET="${1:-$(wslpath "$WIN_HOME")/Downloads/EnterpriseFlow-Windows}"
DEMO_DB="${EF_DEMO_DB:-$HOME/.local/share/enterpriseflow-fb/demo.fdb}"
DISTRO="${WSL_DISTRO_NAME:-Ubuntu}"
mkdir -p "$TARGET/plugins"
cp "$WIN_BUILD/EnterpriseFlowLcl.exe" "$TARGET/EnterpriseFlow.exe"
cp "$CLIENT"/fbclient.dll "$CLIENT"/firebird.msg "$CLIENT"/msvcp140*.dll "$CLIENT"/vcruntime140*.dll "$TARGET/"
cp "$CLIENT"/plugins/* "$TARGET/plugins/"
cat > "$TARGET/enterpriseflow.ini" <<INI
; Banco de demonstracao no WSL, so nesta maquina. Senha padrao de desenvolvimento.
[database]
host=127.0.0.1
port=53050
path=$DEMO_DB
user=SYSDBA
password=masterkey

[integration]
base_url=http://127.0.0.1:8765
timeout_ms=5000

[logging]
path=enterpriseflow.log
INI
printf '@echo off\r\ncd /d "%%~dp0"\r\nwsl.exe -d %s --cd "%s" -- ./scripts/start-demo.sh\r\nif errorlevel 1 (\r\n  echo Nao foi possivel preparar o banco no WSL.\r\n  pause\r\n  exit /b 1\r\n)\r\nstart "" EnterpriseFlow.exe\r\n' "$DISTRO" "$ROOT" > "$TARGET/Abrir EnterpriseFlow.bat"
printf 'EnterpriseFlow ERP: cenario ficticio de portfolio.\r\n\r\nAbra "Abrir EnterpriseFlow.bat". Ele sobe o Firebird e o banco de demonstracao no WSL e abre o programa.\r\n\r\nUsuarios: admin, vendedor1, vendedor2, vendedor3, estoque, financeiro e gerente. Senha de todos: demo1234.\r\n\r\nEsta versao foi compilada com Free Pascal e Lazarus, nao com Delphi.\r\n' > "$TARGET/LEIA-ME.txt"
echo "$TARGET"
