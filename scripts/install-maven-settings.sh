#!/bin/sh
# Install the demo Nexus settings where Maven looks by default: ~/.m2/settings.xml
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "${HOME}/.m2"
cp "$ROOT/settings/nexus-settings.xml" "${HOME}/.m2/settings.xml"
echo "Installed $ROOT/settings/nexus-settings.xml as ${HOME}/.m2/settings.xml"
