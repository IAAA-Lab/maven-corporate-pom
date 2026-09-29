#!/bin/sh
# Hosted internos + group maven-internal. maven-public queda solo con el proxy
# maven-central (externos). Idempotente.
set -eu

NEXUS_URL=${NEXUS_URL:-http://127.0.0.1:8081}
NEXUS_USERNAME=${NEXUS_USERNAME:-admin}
: "${NEXUS_PASSWORD:?NEXUS_PASSWORD is required}"

API="${NEXUS_URL%/}/service/rest/v1"
AUTH="${NEXUS_USERNAME}:${NEXUS_PASSWORD}"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

http_code() {
  method=$1
  path=$2
  extra=${3:-}
  if [ -n "$extra" ]; then
    curl -sS -o "$TMP" -w '%{http_code}' \
      -u "$AUTH" \
      -X "$method" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      --data "$extra" \
      "$API$path"
  else
    curl -sS -o "$TMP" -w '%{http_code}' \
      -u "$AUTH" \
      -X "$method" \
      -H 'Accept: application/json' \
      "$API$path"
  fi
}

ensure_hosted() {
  name=$1
  policy=$2
  code=$(http_code GET "/repositories/maven/hosted/$name")
  if [ "$code" = "200" ]; then
    echo "  El hosted de Nexus ya existe: $name"
    return 0
  fi
  body=$(cat <<EOF
{"name":"$name","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"maven":{"versionPolicy":"$policy","layoutPolicy":"STRICT"}}
EOF
)
  code=$(http_code POST "/repositories/maven/hosted" "$body")
  case "$code" in
    200|201|204) echo "  Creado hosted de Nexus: $name" ;;
    *)
      echo "No se ha podido crear $name: HTTP $code" >&2
      cat "$TMP" >&2
      echo >&2
      return 1
      ;;
  esac
}

allow_redeploy() {
  name=$1
  policy=$2
  body=$(cat <<EOF
{"name":"$name","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"maven":{"versionPolicy":"$policy","layoutPolicy":"STRICT"}}
EOF
)
  code=$(http_code PUT "/repositories/maven/hosted/$name" "$body")
  case "$code" in
    200|204) echo "  Redeploy permitido en $name" ;;
    *) echo "No se ha podido permitir redeploy en $name: HTTP $code" ;;
  esac
}

ensure_group() {
  name=$1
  members=$2
  body=$(cat <<EOF
{"name":"$name","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":$members}}
EOF
)
  code=$(http_code GET "/repositories/maven/group/$name")
  if [ "$code" = "200" ]; then
    code=$(http_code PUT "/repositories/maven/group/$name" "$body")
    case "$code" in
      200|204) echo "  Group $name actualizado" ;;
      *)
        echo "No se ha podido actualizar $name: HTTP $code" >&2
        cat "$TMP" >&2
        echo >&2
        return 1
        ;;
    esac
    return 0
  fi
  code=$(http_code POST "/repositories/maven/group" "$body")
  case "$code" in
    200|201|204) echo "  Creado group $name" ;;
    *)
      echo "No se ha podido crear $name: HTTP $code" >&2
      cat "$TMP" >&2
      echo >&2
      return 1
      ;;
  esac
}

ensure_hosted internal-artifact-releases RELEASE
ensure_hosted internal-artifact-snapshots SNAPSHOT

ensure_group maven-internal '["internal-artifact-releases","internal-artifact-snapshots"]'
ensure_group maven-public '["maven-central"]'

allow_redeploy internal-artifact-releases RELEASE
allow_redeploy internal-artifact-snapshots SNAPSHOT
