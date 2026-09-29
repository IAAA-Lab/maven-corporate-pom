#!/bin/sh
# Set a known admin password on first boot, then create internal hosted repos.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

NEXUS_URL=${NEXUS_URL:-http://127.0.0.1:8081}
export NEXUS_URL
export NEXUS_PASSWORD=${NEXUS_PASSWORD:-admin123}

"$ROOT/scripts/wait-for-nexus.sh"

if docker compose exec -T nexus test -f /nexus-data/admin.password; then
  OLD=$(docker compose exec -T nexus cat /nexus-data/admin.password | tr -d '\r\n')
  echo "  Cambiando el password de admin de Nexus (valor generado en el primer arranque)"
  curl -sf -u "admin:${OLD}" \
    -X PUT \
    -H "Content-Type: text/plain" \
    --data "$NEXUS_PASSWORD" \
    "$NEXUS_URL/service/rest/v1/security/users/admin/change-password"
  echo "  El password de admin de Nexus es el valor de NEXUS_PASSWORD"
else
  echo "  Ya no está el fichero de password del primer arranque; se comprueba NEXUS_PASSWORD"
  curl -sf -u "admin:${NEXUS_PASSWORD}" \
    "$NEXUS_URL/service/rest/v1/status" >/dev/null
  echo "  Nexus ha aceptado NEXUS_PASSWORD"
fi

"$ROOT/scripts/provision-nexus.sh"
