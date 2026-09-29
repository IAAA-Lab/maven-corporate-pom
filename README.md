# Parent y BOM corporativos con Spring Boot 2.7

Ejemplo de plataforma Maven de empresa: **Spring Boot 2.7.18** y **Java 8**.
Dos artefactos distintos, un reactor `corporate` que fija `groupId` y versión:

- `corporate-bom` es el catálogo de versiones (`spring-boot-dependencies` en
  Spring Boot).
- `corporate-parent` es la política de build sobre ese catálogo
  (`spring-boot-starter-parent` en Spring Boot).

Cadena de **parent**:

`greeting-app` / `greeting` → `corporate-parent` → `corporate`

BOM y parent heredan el reactor; el `relativePath` por defecto es
`../pom.xml`. `corporate-parent` importa `corporate-bom` (misma versión
`${project.version}`). Las apps no declaran el BOM ni el reactor.

Este git tiene **tres proyectos Maven**:

1. `corporate` (reactor: `corporate-bom` + `corporate-parent`)
2. `greeting`
3. `greeting-app`

BOM y parent salen con `<revision>` del reactor (**1.0.0**). Un bump de
plataforma en `corporate` es cambiar esa property. `flatten-maven-plugin`
(`resolveCiFriendliesOnly`) deja en Nexus `1.0.0`, no `${revision}`.
`greeting` y `greeting-app` dejan `<relativePath/>` vacío: Maven pide el
parent a Nexus, no a este checkout. Siguen declarando a mano la versión de
`corporate-parent`: no están en el reactor.

## Settings de usuario: dónde se leen los artefactos

El `settings.xml` de cada desarrollador separa **externos** e **internos**.
No hay un group que mezcle ambos.

- **Externos:** `mirrorOf` de `central` hacia el group `maven-public`
  (Compose, puerto 8081). Ese group solo tiene el proxy `maven-central`.
  Lo que Maven pediría a Maven Central va ahí.
- **Internos:** un profile activo con el group `maven-internal` (los dos
  hosted de empresa). El parent con `<relativePath/>` vacío y las
  librerías `dev.example.*` salen de esa URL, no de `maven-public`.

El deploy **no** usa ningún group: usa las URL de `<distributionManagement>`
(hosted `internal-artifact-releases`). Un group de Nexus no admite
`mvn deploy`.

El password no va escrito en git: en el settings está `${env.NEXUS_PASSWORD}`.
El usuario del `<server>` es `admin` (fijo en el fichero de la demo).

## Corporate: coordenadas, metadatos y dónde se publica (`distributionManagement`)

La publicación se declara en `<distributionManagement>` del reactor
`corporate`. Lo heredan el BOM, el parent, `greeting` y `greeting-app`.

El `<id>` (`nexus-internal-releases`) coincide con un `<server>` del
settings (usuario `admin`, password interpolado). Las URL son
`${env.NEXUS_INTERNAL_RELEASES_URL}` y la de snapshots; Maven las interpola
al hacer deploy. El POM que queda en Nexus lleva ya la URL concreta, no la
variable.

## Demostración

Codespace, reconstruir el contenedor (Maven 3.9.9 y Docker-in-Docker) y:

```bash
./demo.sh
```

El settings de usuario por defecto es `~/.m2/settings.xml`.
El repo guarda `settings/nexus-settings.xml`. `./demo.sh` lo copia ahí para que 
`mvn` pueda usar Nexus para consumir artefactos.

Después arranca Nexus y hace deploy del reactor `corporate` (publica
`corporate`, `corporate-bom` y `corporate-parent`) y luego de `greeting`.
Antes de greeting borra `~/.m2/repository/dev/example` para que el parent
no salga del disco. Luego los tests de `greeting-app` (parent, BOM y
librería por `maven-internal`; Spring Boot por `maven-public` → proxy
`maven-central`). Al final, deploy de `greeting-app` con `-DskipTests`.

`greeting` y `greeting-app` declaran `groupId` `dev.example.greeting`. Si no,
heredarían `dev.example.corporate` del parent.

## Estructura elegida

```mermaid
flowchart BT
    subgraph external["Nexus maven-central (proxy público)"]
        bootBom["spring-boot-dependencies 2.7.18"]
    end
    subgraph internal["Nexus internal-artifact-releases"]
        reactor["dev.example.corporate:corporate 1.0.0"]
        bom["dev.example.corporate:corporate-bom 1.0.0"]
        parent["dev.example.corporate:corporate-parent 1.0.0"]
        library["dev.example.greeting:greeting 2.0.0"]
        app["dev.example.greeting:greeting-app 0.1.0"]
    end

    bom -->|"import scope"| bootBom
    bom -->|"parent"| reactor
    parent -->|"parent"| reactor
    parent -->|"import scope"| bom
    library -->|"parent desde Nexus"| parent
    app -->|"parent desde Nexus"| parent
    app -->|"dependency, sin version"| library
```

## Versionado

Versión de plataforma, versiones gestionadas y versión de producto son
independientes.

```mermaid
flowchart LR
    reactor["corporate 1.0.0"]
    bom["corporate-bom 1.0.0"]
    parent["corporate-parent 1.0.0"]
    boot["Spring Boot 2.7.18"]
    library["greeting 2.0.0"]
    product["greeting-app 0.1.0"]

    bom -->|"parent"| reactor
    parent -->|"parent"| reactor
    parent -->|"import"| bom
    bom -->|"manages"| boot
    bom -->|"manages"| library
    library -->|"parent"| parent
    product -->|"parent"| parent
    product -->|"usa versión gestionada"| library
```

- **Plataforma:** `<revision>` en `corporate/pom.xml`. BOM y parent usan
  `${revision}` en el GAV del padre. La aplicación elige plataforma
  cambiando la versión de `corporate-parent`.
- **Gestionadas:** el BOM fija Spring Boot y librerías internas aprobadas. No
  tienen que coincidir con la versión de plataforma.
- **Producto:** cada librería y aplicación declara su versión. Si no, heredaría
  la de la plataforma y se publicaría como si fuera la plataforma.

Cambiar la línea de Spring Boot exige un release nuevo de plataforma. Las
apps ya publicadas no se actualizan solas:

```mermaid
flowchart LR
    oldApp["App parent 1.0.0"]
    oldPlatform["Plataforma 1.0.0: Boot 2.7.18"]
    newPlatform["Plataforma 1.1.0: catálogo nuevo"]
    upgradedApp["App parent 1.1.0"]

    oldApp -->|"parent"| oldPlatform
    upgradedApp -->|"parent"| newPlatform
    oldPlatform -->|"nuevo release de plataforma"| newPlatform
```

`spring-boot.version` está en el reactor: el BOM la usa al importar
`spring-boot-dependencies` y el parent al fijar `spring-boot-maven-plugin`.
Un import de BOM no transmite properties.

## Repositorios

Nexus OSS trae de serie el group `maven-public` (con hosted vacíos de
ejemplo más el proxy `maven-central`). Esta demo deja `maven-public` **solo**
con `maven-central`: es el group de **externos**. Añade dos hosted de
empresa y el group `maven-internal` con esos miembros, en este orden:
`internal-artifact-releases`, `internal-artifact-snapshots`. Eso es el
group de **internos**.

Los groups son URL de lectura. El proxy `maven-central` es quien habla con
Maven Central en internet. El deploy escribe en el hosted
(`distributionManagement`), no en `maven-internal`.

```mermaid
flowchart TB
    app["greeting-app"]
    settings["~/.m2/settings.xml"]

    subgraph nexus["Nexus"]
        subgraph pub["group maven-public — externos"]
            proxy["proxy maven-central"]
        end
        subgraph intern["group maven-internal — internos"]
            hostedRel["hosted internal-artifact-releases"]
            hostedSnap["hosted internal-artifact-snapshots"]
        end
    end

    internet["Maven Central"]

    app --> settings
    settings -->|"mirrorOf central"| pub
    settings -->|"repositorio maven-internal"| intern
    proxy -->|"origen remoto"| internet
    app -->|"deploy: distributionManagement"| hostedRel
```

## Fuentes

- [Spring Boot Maven plugin: using Boot without its parent](https://docs.spring.io/spring-boot/docs/2.7.18/maven-plugin/reference/htmlsingle/#using-boot)
- [Maven settings reference](https://maven.apache.org/settings.html)
- [Maven mirror guide](https://maven.apache.org/guides/mini/guide-mirror-settings)
- [Sonatype: why repositories in POMs are problematic](https://www.sonatype.com/blog/2009/02/why-putting-repositories-in-your-poms-is-a-bad-idea)
- [Nexus Repository REST: repositories](https://help.sonatype.com/en/repositories-api.html)
- [Maven CI-friendly versions](https://maven.apache.org/maven-ci-friendly.html)
- [JLBP-15: publish a BOM for multi-module projects](http://jlbp.dev/JLBP-15)
