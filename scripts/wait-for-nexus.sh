#!/bin/sh
# Wait until Nexus REST status is reachable on the published port.
set -eu

NEXUS_URL=${NEXUS_URL:-http://127.0.0.1:8081}
ATTEMPTS=${NEXUS_WAIT_ATTEMPTS:-60}

i=1
while [ "$i" -le "$ATTEMPTS" ]; do
  if curl -sf "$NEXUS_URL/service/rest/v1/status" >/dev/null; then
    echo "Nexus is up at $NEXUS_URL"
    exit 0
  fi
  echo "Waiting for Nexus ($i/$ATTEMPTS)..."
  i=$((i + 1))
  sleep 5
done

echo "Nexus did not become ready at $NEXUS_URL" >&2
exit 1
