#!/bin/sh
# Un git: reactor corporate (BOM + parent) y dos productos. Un Nexus.
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

heading 4 "Deploy de corporate 1.0.0 → internal-artifact-releases"
note "El reactor publica corporate, corporate-bom y corporate-parent con el mismo groupId y versión."
note "Coordinate:  dev.example.corporate:corporate:1.0.0"
$MVN -f "$ROOT/corporate/pom.xml" deploy
ok "Publicado el reactor (BOM + parent) en internal-artifact-releases"

heading 5 "Deploy de greeting 2.0.0 → internal-artifact-releases"
note "La librería hereda corporate-parent. groupId dev.example.greeting, no corporate."
note "relativePath vacío: el parent se pide a maven-internal, no a maven-public."
wipe_local
note "Coordinate:  dev.example.greeting:greeting:2.0.0"
$MVN -f "$ROOT/greeting/pom.xml" deploy
ok "Publicado en internal-artifact-releases (parent resuelto en Nexus)"

heading 6 "Test de greeting-app 0.1.0 contra Nexus"
note "La aplicación también hereda corporate-parent. Sin version en spring-boot-starter"
note "ni greeting: las tiene que poner el BOM o el modelo no es válido."
wipe_local
note "Coordinate:  dev.example.greeting:greeting-app:0.1.0"
$MVN -f "$ROOT/greeting-app/pom.xml" test
ok "Tests OK (Hola, Codespaces). Internos por maven-internal; Spring Boot por maven-public."

heading 7 "Deploy de greeting-app 0.1.0 → internal-artifact-releases"
$MVN -f "$ROOT/greeting-app/pom.xml" deploy -DskipTests
ok "Publicado en internal-artifact-releases"

echo
echo "========================================================================"
echo "  Hecho"
echo "========================================================================"
note "Internos (maven-internal → hosted):  corporate, corporate-bom, corporate-parent, greeting, greeting-app"
note "Externos (maven-public → maven-central): Spring Boot y el resto de Central"
note "UI: $NEXUS_URL"
echo
