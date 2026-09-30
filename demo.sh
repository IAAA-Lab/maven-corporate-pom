#!/bin/sh
# Un git: reactor corporate (corporate-bom + corporate-parent) y dos productos. Un Nexus.
# Internos: hosted + group maven-internal. Externos: maven-public = proxy maven-central.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

export NEXUS_URL=${NEXUS_URL:-http://127.0.0.1:8081}
export NEXUS_PASSWORD=${NEXUS_PASSWORD:-admin123}
export NEXUS_INTERNAL_RELEASES_URL=${NEXUS_INTERNAL_RELEASES_URL:-$NEXUS_URL/repository/internal-artifact-releases/}
export NEXUS_INTERNAL_SNAPSHOTS_URL=${NEXUS_INTERNAL_SNAPSHOTS_URL:-$NEXUS_URL/repository/internal-artifact-snapshots/}

TOTAL=7
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
  note "Borrado ~/.m2/repository/dev/example para que el siguiente build no use una copia local."
}

# First <version> after </parent>: the project's own version, not the parent's.
own_version() {
  sed -n '/<\/parent>/,$ s:.*<version>\(.*\)</version>.*:\1:p' "$1" | head -n 1
}

hosted_for() {
  case "$1" in
    *-SNAPSHOT) echo internal-artifact-snapshots ;;
    *) echo internal-artifact-releases ;;
  esac
}

PLATFORM=$(sed -n 's/^-Drevision=//p' "$ROOT/corporate/.mvn/maven.config")
LIBRARY=$(own_version "$ROOT/greeting/pom.xml")
APP=$(own_version "$ROOT/greeting-app/pom.xml")

echo
echo "Demo de la plataforma Maven corporativa"
note "Reactor corporate (BOM + parent). greeting y greeting-app resuelven el parent en Nexus."
note "Maven va en silencio; estos pasos son el log."

heading 1 "Instalar el settings de usuario de Maven"
note "El fichero por defecto es ~/.m2/settings.xml (no cabe en git)."
note "Se copia settings/nexus-settings.xml para que un mvn sin flags use Nexus."
mkdir -p "${HOME}/.m2"
rm -f "${HOME}/.m2/settings.xml"
cp "$ROOT/settings/nexus-settings.xml" "${HOME}/.m2/settings.xml"
ok "Instalado ~/.m2/settings.xml  (externos: maven-public; internos: maven-internal)"

heading 2 "Arrancar Nexus OSS"
note "Compose levanta sonatype/nexus3 en el puerto 8081."
docker compose up -d --quiet-pull
ok "Contenedor en marcha. El primer arranque puede tardar un minuto."

heading 3 "Esperar a Nexus y provisionar repositorios"
note "Password de admin. Hosted internos y group maven-internal para la empresa."
note "maven-public queda solo con el proxy maven-central (Spring Boot, …)."
note "Redeploy permitido en los hosted para poder repetir el script."
"$ROOT/scripts/bootstrap-nexus.sh"
ok "Listo. UI: $NEXUS_URL  (admin / NEXUS_PASSWORD)"

heading 4 "Deploy de la plataforma $PLATFORM → $(hosted_for "$PLATFORM")"
note "Un reactor, una revision (corporate/.mvn/maven.config). deployAtEnd: suben juntos."
note "Coordinates: dev.example.corporate:corporate-bom:$PLATFORM, dev.example.corporate:corporate-parent:$PLATFORM"
wipe_local
$MVN -f "$ROOT/corporate/pom.xml" deploy
ok "Publicados corporate-bom y corporate-parent en $(hosted_for "$PLATFORM")"

heading 5 "Deploy de greeting $LIBRARY → $(hosted_for "$LIBRARY")"
note "La librería hereda corporate-parent. groupId dev.example.greeting, no corporate."
note "relativePath vacío: el parent se pide a maven-internal, no a maven-public."
wipe_local
note "Coordinate:  dev.example.greeting:greeting:$LIBRARY"
$MVN -f "$ROOT/greeting/pom.xml" deploy
ok "Publicado en $(hosted_for "$LIBRARY") (parent resuelto en Nexus)"

heading 6 "Test de greeting-app $APP contra Nexus"
note "La aplicación también hereda corporate-parent. Sin version en spring-boot-starter"
note "ni greeting: las pone corporate-bom, padre del parent. El modelo no es válido si faltan."
wipe_local
note "Coordinate:  dev.example.greeting:greeting-app:$APP"
$MVN -f "$ROOT/greeting-app/pom.xml" test
ok "Tests OK (Hola, Codespaces). Internos por maven-internal; Spring Boot por maven-public."

heading 7 "Deploy de greeting-app $APP → $(hosted_for "$APP")"
$MVN -f "$ROOT/greeting-app/pom.xml" deploy -DskipTests
ok "Publicado en $(hosted_for "$APP")"

echo
echo "========================================================================"
echo "  Hecho"
echo "========================================================================"
note "Internos (maven-internal → hosted):  corporate-bom, corporate-parent, greeting, greeting-app"
note "Externos (maven-public → maven-central): Spring Boot y el resto de Central"
note "UI: $NEXUS_URL"
echo
