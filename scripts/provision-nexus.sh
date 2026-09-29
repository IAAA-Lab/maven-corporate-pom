#!/bin/sh
# Create internal hosted Maven repos and attach them to maven-public. Idempotent.
# Public artifacts (Spring Boot, …) stay on the maven-central proxy.
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
    echo "  Nexus hosted repository already exists: $name"
    return 0
  fi
  body=$(cat <<EOF
{"name":"$name","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"maven":{"versionPolicy":"$policy","layoutPolicy":"STRICT"}}
EOF
)
  code=$(http_code POST "/repositories/maven/hosted" "$body")
  case "$code" in
    200|201|204) echo "  Created Nexus hosted repository: $name" ;;
    *)
      echo "Could not create $name: HTTP $code" >&2
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
    200|204) echo "  Redeploy allowed on $name" ;;
    *) echo "Could not allow redeploy on $name: HTTP $code" ;;
  esac
}

ensure_hosted internal-artifact-releases RELEASE
ensure_hosted internal-artifact-snapshots SNAPSHOT

group_body=$(cat <<'EOF'
{"name":"maven-public","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":["internal-artifact-releases","internal-artifact-snapshots","maven-central"]}}
EOF
)
code=$(http_code PUT "/repositories/maven/group/maven-public" "$group_body")
case "$code" in
  200|204) echo "  maven-public = internal hosted + maven-central (public proxy)" ;;
  *)
    echo "Could not update maven-public: HTTP $code" >&2
    cat "$TMP" >&2
    echo >&2
    exit 1
    ;;
esac

allow_redeploy internal-artifact-releases RELEASE
allow_redeploy internal-artifact-snapshots SNAPSHOT
