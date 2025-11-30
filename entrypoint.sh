#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$1"
SOURCE_LEVEL="$2"
EXTRA_CLASSPATH="$3"
CLEANUP_OPTIONS_JSON="$4"

POM_FILE="$PROJECT_ROOT/refactoring-cli/pom.xml"

echo "Extracting Eclipse release from pom.xml..."

ECLIPSE_REPO=$(grep -oPm1 "(?<=<eclipse.release.repo>)[^<]+" "$POM_FILE")
# Example: https://download.eclipse.org/releases/2025-09

ECLIPSE_VERSION=$(basename "$ECLIPSE_REPO")
# Extracts: 2025-09

ECLIPSE_PACKAGE="java"  # internal decision — not user-configurable

echo "Detected Eclipse release: $ECLIPSE_VERSION"

echo "Downloading Eclipse..."
eclipse-download "$ECLIPSE_VERSION" "$ECLIPSE_PACKAGE"

ECLIPSE_HOME=$(cat /opt/eclipse_home)

echo "Installing plugin..."
mkdir -p "$ECLIPSE_HOME/dropins/refactoring-cli"
cp /opt/refactoring-cli-plugin.jar "$ECLIPSE_HOME/dropins/refactoring-cli/"

echo "Running cleanup..."
"$ECLIPSE_HOME/eclipse" \
  -nosplash \
  -application io.github.nbauma109.refactoring.cli.app \
  --source "$SOURCE_LEVEL" \
  --classpath "$EXTRA_CLASSPATH" \
  --cleanup-options "$CLEANUP_OPTIONS_JSON" \
  "$PROJECT_ROOT"
