#!/usr/bin/env bash
# Instala Firebird 5 no diretorio do usuario, sem root nem Docker, e sobe o servidor na porta
# 53050. So para desenvolvimento e CI: a senha fixa aqui nao protege nada de verdade.
set -euo pipefail
VERSION=5.0.4
BUILD=1812
PREFIX="${EF_FB_PREFIX:-$HOME/.local/firebird-5}"
FB="$PREFIX/opt/firebird"
PORT="${EF_TEST_DB_PORT:-53050}"
PASSWORD="${EF_TEST_DB_PASSWORD:-masterkey}"
if [ ! -x "$FB/bin/firebird" ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  curl -fsSL -o "$WORK/fb.tar.gz" "https://github.com/FirebirdSQL/firebird/releases/download/v$VERSION/Firebird-$VERSION.$BUILD-0-linux-x64.tar.gz"
  tar xzf "$WORK/fb.tar.gz" -C "$WORK"
  mkdir -p "$PREFIX"
  tar xzf "$WORK"/Firebird-*/buildroot.tar.gz -C "$PREFIX"
  if ! ldconfig -p | grep -q libtommath.so.1; then
    (cd "$WORK" && apt-get download libtommath1 && dpkg -x libtommath1*.deb tm)
    cp -a "$WORK"/tm/usr/lib/x86_64-linux-gnu/libtommath.so.1* "$FB/lib/"
  fi
fi
export FIREBIRD="$FB" LD_LIBRARY_PATH="$FB/lib:${LD_LIBRARY_PATH:-}" FIREBIRD_LOCK="$FB/lock" FIREBIRD_TMP="$FB/tmp"
mkdir -p "$FIREBIRD_LOCK" "$FIREBIRD_TMP" "$HOME/.local/share/enterpriseflow-fb"
sed -i "s/^#\?\s*RemoteServicePort\s*=.*/RemoteServicePort = $PORT/; s/^#\?\s*RemoteBindAddress\s*=.*/RemoteBindAddress = 127.0.0.1/" "$FB/firebird.conf"
printf "create or alter user SYSDBA password '%s' using plugin Srp;\ncommit;\nexit;\n" "$PASSWORD" | "$FB/bin/isql" -q -user SYSDBA security.db >/dev/null
if ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  nohup "$FB/bin/firebird" >"$PREFIX/firebird.out" 2>&1 &
  for _ in $(seq 1 50); do
    (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break
    sleep 0.2
  done
fi
echo "Firebird $VERSION ouvindo em 127.0.0.1:$PORT"
echo "Cliente: export LD_LIBRARY_PATH=$FB/lib:\$LD_LIBRARY_PATH"
