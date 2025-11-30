#!/bin/bash
set -euo pipefail

PROJECT_ROOT="${INPUT_PROJECT_ROOT:-}"
SOURCE_LEVEL="${INPUT_SOURCE_LEVEL:-}"
EXTRA_CLASSPATH="${INPUT_EXTRA_CLASSPATH:-}"

if [ -z "$PROJECT_ROOT" ]; then
  echo "FATAL: INPUT_PROJECT_ROOT is required"; exit 1
fi
if [ -z "$SOURCE_LEVEL" ]; then
  echo "FATAL: INPUT_SOURCE_LEVEL is required"; exit 1
fi

# Convert to absolute paths
PROJECT_ROOT="$(realpath "$PROJECT_ROOT")"

if [ -n "$EXTRA_CLASSPATH" ]; then
  EXTRA_CLASSPATH="$(realpath "$EXTRA_CLASSPATH")"
fi

# ------------------------------
# Extract pom.xml from plugin
# ------------------------------
PLUGIN_JAR="/opt/io.github.nbauma109.refactoring.cli-1.0.0.jar"

if [ ! -f "$PLUGIN_JAR" ]; then
  echo "FATAL: plugin JAR not found at $PLUGIN_JAR"; exit 1
fi

TMP_POM_DIR="$HOME/refactoring-cli"
mkdir -p "$TMP_POM_DIR"

jar xf "$PLUGIN_JAR" \
  META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml

if [ ! -f META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml ]; then
  echo "FATAL: Could not extract pom.xml from plugin JAR."; exit 1
fi

mkdir -p "$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli"
mv META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml \
   "$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml"

rm -rf META-INF

POM="$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml"

ECLIPSE_REPO_URL=$(grep -oPm1 "(?<=<eclipse.release.repo>)[^<]+" "$POM" || true)

ECLIPSE_VERSION="${ECLIPSE_REPO_URL##*/}"

if [ -z "$ECLIPSE_VERSION" ]; then
  echo "FATAL: Could not extract Eclipse version from pom.xml"; exit 1
fi

echo "Using Eclipse release: $ECLIPSE_VERSION"

rm -rf "$TMP_POM_DIR"

# ------------------------------
# Download Eclipse
# ------------------------------
eclipse-download "$ECLIPSE_VERSION" "java"

ECLIPSE_HOME=$(cat /opt/eclipse_home)

echo "Installing plugin $PLUGIN_JAR into $ECLIPSE_HOME/dropins/ ..."
cp "$PLUGIN_JAR" "$ECLIPSE_HOME/dropins/"

# ------------------------------
# Generate cleanup XML profile
# ------------------------------
PROFILE_FILE="$HOME/cleanup-profile.xml"

cat > "$PROFILE_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<profiles version="2">
  <profile kind="CleanUpProfile" name="github-action" version="2">
EOF

while IFS='=' read -r key val; do
  if [[ "$key" =~ ^INPUT_CLEANUP_ ]]; then
    raw="${key#INPUT_CLEANUP_}"
    setting=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr '_' '.')
    echo "    <setting id=\"cleanup.$setting\" value=\"$val\"/>" >> "$PROFILE_FILE"
  fi
done < <(env)

cat >> "$PROFILE_FILE" <<EOF
  </profile>
</profiles>
EOF

echo "Generated cleanup profile:"
cat "$PROFILE_FILE"

# ------------------------------
# Run cleanup
# ------------------------------

WORKSPACE="$HOME/eclipse-workspace"
mkdir -p "$WORKSPACE"

echo "Running Eclipse cleanup using workspace: $WORKSPACE"

set +e
"$ECLIPSE_HOME/eclipse" \
  -nosplash \
  -data "$WORKSPACE" \
  -application io.github.nbauma109.refactoring.cli.app \
  --profile "$PROFILE_FILE" \
  --source "$SOURCE_LEVEL" \
  --classpath "$EXTRA_CLASSPATH" \
  "$PROJECT_ROOT"

EXIT_CODE=$?
set -e

echo "Eclipse exit code: $EXIT_CODE"

# ------------------------------
# Show log if Eclipse failed
# ------------------------------

LOG_FILE="$WORKSPACE/.metadata/.log"

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "=========================================="
  echo "Eclipse reported an error."
  echo "Log file path: $LOG_FILE"
  echo "=========================================="

  if [ -f "$LOG_FILE" ]; then
    echo "---------- ECLIPSE LOG BEGIN ----------"
    cat "$LOG_FILE"
    echo "----------- ECLIPSE LOG END -----------"
  else
    echo "No Eclipse log file found!"
  fi

  exit "$EXIT_CODE"
else
  echo "Cleanup completed successfully."
fi
