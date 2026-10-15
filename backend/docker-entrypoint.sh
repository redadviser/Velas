#!/bin/sh
# Arranque do contentor. Um "Persistent Directory" do CapRover (ou outro volume)
# montado em UPLOAD_DIR pode chegar com dono root, e a API (utilizador node) não
# conseguiria gravar fotografias. Ainda como root, acerta o dono da pasta e só
# depois arranca a API sem privilégios.
set -e
if [ "$(id -u)" = "0" ]; then
  mkdir -p "$UPLOAD_DIR"
  chown -R node:node "$UPLOAD_DIR" || echo "Aviso: não foi possível mudar o dono de $UPLOAD_DIR" >&2
  if command -v setpriv >/dev/null 2>&1; then
    exec setpriv --reuid=node --regid=node --init-groups "$@"
  fi
  echo "Aviso: setpriv não existe; a API vai correr como root." >&2
fi
exec "$@"
