#!/bin/sh
# Four independent Maven projects, one git repo, one Nexus.
# Company artifacts go to internal-artifact-releases; public imports stay on maven-central.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

export NEXUS_URL=${NEXUS_URL:-http://127.0.0.1:8081}
export NEXUS_PASSWORD=${NEXUS_PASSWORD:-admin123}
export NEXUS_INTERNAL_RELEASES_URL=${NEXUS_INTERNAL_RELEASES_URL:-$NEXUS_URL/repository/internal-artifact-releases/}
export NEXUS_INTERNAL_SNAPSHOTS_URL=${NEXUS_INTERNAL_SNAPSHOTS_URL:-$NEXUS_URL/repository/internal-artifact-snapshots/}

TOTAL=8
MVN="mvn --batch-mode --quiet --no-transfer-progress"

heading() {
  echo
  echo "========================================================================"
  printf '  [%s/%s]  %s\n' "$1" "$TOTAL" "$2"
  echo "========================================================================"
}

note() {
  printf '  %s\n' "$1"
}

ok() {
  printf '  OK  %s\n' "$1"
}

wipe_local() {
  rm -rf "${HOME}/.m2/repository/dev/example"
  note "Cleared ~/.m2/repository/dev/example so the next build cannot use a local copy."
}

echo
echo "Corporate Maven platform demo"
note "Four independent projects. Parents resolve from Nexus, not from this checkout."
note "Maven itself is quiet; these steps are the log."

heading 1 "Install Maven user settings"
note "Maven’s default file is ~/.m2/settings.xml (not something git can hold)."
note "Copy settings/nexus-settings.xml there so a plain mvn command uses Nexus."
mkdir -p "${HOME}/.m2"
rm -f "${HOME}/.m2/settings.xml"
cp "$ROOT/settings/nexus-settings.xml" "${HOME}/.m2/settings.xml"
ok "Installed ~/.m2/settings.xml  (mirrorOf central → maven-public at $NEXUS_URL)"

heading 2 "Start Nexus OSS"
note "Compose starts sonatype/nexus3 and publishes it on port 8081."
docker compose up -d --quiet-pull
ok "Container is up. First boot can take a minute."

heading 3 "Wait for Nexus and provision repositories"
note "Set the admin password. Hosted internal-artifact-releases holds company artifacts."
note "The maven-central proxy holds public imports (Spring Boot, …)."
note "maven-public groups both. Redeploy is allowed so this script can be repeated."
"$ROOT/scripts/bootstrap-nexus.sh"
ok "Ready. Browse $NEXUS_URL  (admin / NEXUS_PASSWORD)"

heading 4 "Deploy corporate-bom 1.0.0 → internal-artifact-releases"
note "Version catalogue: imports spring-boot-dependencies (from maven-central) and pins greeting 2.0.0."
note "Coordinate:  dev.example.corporate:corporate-bom:1.0.0"
$MVN -f "$ROOT/corporate-bom/pom.xml" deploy
ok "Published to internal-artifact-releases"

heading 5 "Deploy corporate-parent 1.0.0 → internal-artifact-releases"
note "Build policy on top of the BOM (compiler, enforcer, plugin versions)."
note "Empty relativePath: parent is the BOM already in Nexus, not ../pom.xml."
wipe_local
note "Coordinate:  dev.example.corporate:corporate-parent:1.0.0"
$MVN -f "$ROOT/corporate-parent/pom.xml" deploy
ok "Published to internal-artifact-releases (corporate-bom resolved from Nexus)"

heading 6 "Deploy greeting 2.0.0 → internal-artifact-releases"
note "Library inherits corporate-parent. groupId is dev.example.greeting, not corporate."
note "Empty relativePath: parent is fetched from maven-public. Same hosted repo as the platform."
wipe_local
note "Coordinate:  dev.example.greeting:greeting:2.0.0"
$MVN -f "$ROOT/greeting/pom.xml" deploy
ok "Published to internal-artifact-releases (parent resolved from Nexus)"

heading 7 "Test greeting-app 0.1.0 against Nexus"
note "Application also inherits corporate-parent. No versions on spring-boot-starter"
note "or greeting: the BOM must supply them or the model is invalid."
wipe_local
note "Coordinate:  dev.example.greeting:greeting-app:0.1.0"
$MVN -f "$ROOT/greeting-app/pom.xml" test
ok "Tests passed (Hello, Codespaces). Internal artifacts and Spring Boot came through maven-public."

heading 8 "Deploy greeting-app 0.1.0 → internal-artifact-releases"
$MVN -f "$ROOT/greeting-app/pom.xml" deploy -DskipTests
ok "Published to internal-artifact-releases"

echo
echo "========================================================================"
echo "  Done"
echo "========================================================================"
note "Internal  (internal-artifact-releases):  corporate-bom, corporate-parent, greeting, greeting-app"
note "Public    (maven-central proxy):         Spring Boot and other Central artifacts"
note "Consume both through maven-public. UI: $NEXUS_URL"
echo
