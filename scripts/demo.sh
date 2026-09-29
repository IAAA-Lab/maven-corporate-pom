#!/bin/sh
# Three independent Maven projects, one git repo, one Nexus.
# Platform POMs go to maven-releases; products go to products-releases.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

export NEXUS_URL=${NEXUS_URL:-http://127.0.0.1:8081}
export NEXUS_PASSWORD=${NEXUS_PASSWORD:-admin123}
export NEXUS_RELEASES_URL=${NEXUS_RELEASES_URL:-$NEXUS_URL/repository/maven-releases/}
export NEXUS_SNAPSHOTS_URL=${NEXUS_SNAPSHOTS_URL:-$NEXUS_URL/repository/maven-snapshots/}
export NEXUS_PRODUCTS_RELEASES_URL=${NEXUS_PRODUCTS_RELEASES_URL:-$NEXUS_URL/repository/products-releases/}
export NEXUS_PRODUCTS_SNAPSHOTS_URL=${NEXUS_PRODUCTS_SNAPSHOTS_URL:-$NEXUS_URL/repository/products-snapshots/}

SETTINGS="$ROOT/settings/nexus-settings.xml"
MVN="mvn --batch-mode --no-transfer-progress --settings $SETTINGS"

wipe_local() {
  rm -rf "${HOME}/.m2/repository/dev/example/corporate-parent"
  rm -rf "${HOME}/.m2/repository/dev/example.build/corporate-bom"
  rm -rf "${HOME}/.m2/repository/dev/example/greeting"
  rm -rf "${HOME}/.m2/repository/dev/example/greeting-app"
}

docker compose up -d
"$ROOT/scripts/bootstrap-nexus.sh"

echo "Deploying corporate BOM and parent to maven-releases"
$MVN -f "$ROOT/pom.xml" deploy

wipe_local
echo "Deploying greeting to products-releases (parent resolved from Nexus)"
$MVN -f "$ROOT/greeting/pom.xml" deploy

wipe_local
echo "Testing and deploying greeting-app (parent and greeting resolved from Nexus)"
$MVN -f "$ROOT/greeting-app/pom.xml" test
$MVN -f "$ROOT/greeting-app/pom.xml" deploy

echo "demo.sh finished: platform in maven-releases, products in products-releases"
