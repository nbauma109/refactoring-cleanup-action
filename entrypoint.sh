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

# ------------------------------
# Extract pom.xml from plugin
# ------------------------------
PLUGIN_JAR="/opt/io.github.nbauma109.refactoring.cli-1.0.0.jar"

if [ ! -f "$PLUGIN_JAR" ]; then
  echo "FATAL: plugin JAR not found at $PLUGIN_JAR"; exit 1
fi

TMP_POM_DIR="/tmp/refactoring-cli"
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
PROFILE_FILE="/tmp/cleanup-profile.xml"

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

WORKSPACE="/tmp/eclipse-workspace"
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

echo
echo "=========== ECLIPSE LOG OUTPUT ==========="

LOG_DIR="$ECLIPSE_HOME/configuration"

if [ -d "$LOG_DIR" ]; then
    echo "Log directory: $LOG_DIR"
    echo "Contents:"
    ls -al "$LOG_DIR"

    LOG_FILE=$(ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -1 || true)

    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        echo
        echo "Showing latest log file: $LOG_FILE"
        echo "------------------------------------"
        cat "$LOG_FILE"
        echo
    else
        echo "No .log file found in configuration directory."
    fi
else
    echo "Log directory does not exist: $LOG_DIR"
fi

echo "=========================================="
echo "Eclipse exit code = $EXIT_CODE"

if [ "$EXIT_CODE" -ne 0 ]; then
    echo "ERROR: Eclipse terminated with failure."
    exit "$EXIT_CODE"
fi
