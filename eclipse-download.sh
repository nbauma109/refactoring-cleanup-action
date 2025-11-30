#!/bin/bash
set -euo pipefail

VERSION="$1"
PACKAGE="$2"

BASE="technology/epp/downloads/release/${VERSION}/R"
FILE="eclipse-${PACKAGE}-${VERSION}-R-linux-gtk-x86_64.tar.gz"

URL="https://www.eclipse.org/downloads/download.php?file=/${BASE}/${FILE}&r=1"

echo "Downloading Eclipse:"
echo "$URL"

curl -L "$URL" -o /tmp/eclipse.tar.gz

mkdir -p /opt/eclipse-unpacked
tar -xf /tmp/eclipse.tar.gz -C /opt/eclipse-unpacked

# Detect real installation dir (usually /opt/eclipse-unpacked/eclipse)
ECLIPSE_DIR=$(find /opt/eclipse-unpacked -maxdepth 1 -type d -name "eclipse*" | head -1)

if [ -z "$ECLIPSE_DIR" ]; then
  echo "ERROR: Cannot locate extracted Eclipse folder"
  exit 1
fi

echo "$ECLIPSE_DIR" > /opt/eclipse_home

echo "Eclipse installed at: $ECLIPSE_DIR"
