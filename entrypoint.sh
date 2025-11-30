#!/bin/bash
set -euo pipefail

# --------------------------------------------------------------------
# Inputs from GitHub Action (all optional → default to empty string)
# --------------------------------------------------------------------

PROJECT_ROOT="${INPUT_PROJECT_ROOT:-}"
SOURCE_LEVEL="${INPUT_SOURCE_LEVEL:-}"
EXTRA_CLASSPATH="${INPUT_EXTRA_CLASSPATH:-}"
CLEANUP_OPTIONS_JSON="${INPUT_CLEANUP_OPTIONS_JSON:-}"

# Fail hard if mandatory ones are missing
if [ -z "$PROJECT_ROOT" ]; then
    echo "FATAL: INPUT_PROJECT_ROOT is required."
    exit 1
fi

if [ -z "$SOURCE_LEVEL" ]; then
    echo "FATAL: INPUT_SOURCE_LEVEL is required."
    exit 1
fi

if [ -z "$CLEANUP_OPTIONS_JSON" ]; then
    echo "FATAL: INPUT_CLEANUP_OPTIONS_JSON is required."
    exit 1
fi

# --------------------------------------------------------------------
# Extract Eclipse release version from plugin JAR pom.xml
# --------------------------------------------------------------------

echo "Extracting Eclipse release tag from embedded plugin POM..."

TMP_DIR="/tmp/refactoring-cli-pom"
mkdir -p "$TMP_DIR"

jar xf /opt/refactoring-cli-plugin.jar \
  META-INF/maven/io.github.nbauma109/refactoring-cli/pom.xml

# Move to predictable temp path
if [ -f "META-INF/maven/io.github.nbauma109/refactoring-cli/pom.xml" ]; then
    mkdir -p "$TMP_DIR/META-INF/maven/io.github.nbauma109/"
    mv META-INF/maven/io.github.nbauma109/refactoring-cli/pom.xml "$TMP_DIR/META-INF/maven/io.github.nbauma109/"
    rm -rf META-INF
fi

POM="$TMP_DIR/META-INF/maven/io.github.nbauma109/refactoring-cli/pom.xml"

if [ ! -f "$POM" ]; then
    echo "FATAL: pom.xml could not be extracted from plugin jar!"
    exit 1
fi

ECLIPSE_REPO_URL=$(grep -oPm1 "(?<=<eclipse.release.repo>)[^<]+" "$POM" || true)

if [ -z "$ECLIPSE_REPO_URL" ]; then
    echo "FATAL: eclipse.release.repo not found inside plugin pom.xml!"
    exit 1
fi

echo "Found eclipse.release.repo: $ECLIPSE_REPO_URL"

# Convert:
#   https://download.eclipse.org/releases/2025-09
# →  "2025-09"
ECLIPSE_VERSION="${ECLIPSE_REPO_URL##*/}"

echo "Using Eclipse version: $ECLIPSE_VERSION"

rm -rf "$TMP_DIR"

# --------------------------------------------------------------------
# Download Eclipse
# --------------------------------------------------------------------

echo "Downloading Eclipse $ECLIPSE_VERSION..."
eclipse-download "$ECLIPSE_VERSION" "java"

ECLIPSE_HOME=$(cat /opt/eclipse_home)
echo "ECLIPSE_HOME = $ECLIPSE_HOME"

# --------------------------------------------------------------------
# Install plugin jar into dropins
# --------------------------------------------------------------------

echo "Installing plugin into Eclipse dropins..."
mkdir -p "$ECLIPSE_HOME/dropins/refactoring-cli"
cp /opt/refactoring-cli-plugin.jar "$ECLIPSE_HOME/dropins/refactoring-cli/"

# --------------------------------------------------------------------
# Run cleanup tool
# --------------------------------------------------------------------

echo "Running cleanup..."

"$ECLIPSE_HOME/eclipse" \
  -nosplash \
  -application io.github.nbauma109.refactoring.cli.app \
  --source "$SOURCE_LEVEL" \
  --classpath "$EXTRA_CLASSPATH" \
  --cleanup-options "$CLEANUP_OPTIONS_JSON" \
  "$PROJECT_ROOT"

echo "Cleanup complete."
