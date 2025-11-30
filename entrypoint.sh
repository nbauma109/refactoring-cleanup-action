#!/bin/bash
set -euo pipefail

# ------------------------------
# Read required inputs
# ------------------------------

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

# Normalize EXTRA_CLASSPATH into absolute paths
if [ -n "$EXTRA_CLASSPATH" ]; then
  ABS_CLASSPATH=""
  IFS=':' read -ra CP_ENTRIES <<< "$EXTRA_CLASSPATH"
  for entry in "${CP_ENTRIES[@]}"; do
    if [ -z "$entry" ]; then
      continue
    fi
    abs="$(realpath "$entry")"
    ABS_CLASSPATH="${ABS_CLASSPATH:+$ABS_CLASSPATH:}$abs"
  done
  EXTRA_CLASSPATH="$ABS_CLASSPATH"
fi

# ------------------------------
# Extract pom.xml from plugin
# ------------------------------

PLUGIN_JAR="/opt/io.github.nbauma109.refactoring.cli-1.0.0.jar"

if [ ! -f "$PLUGIN_JAR" ]; then
  echo "FATAL: plugin JAR not found at $PLUGIN_JAR"
  exit 1
fi

TMP_POM_DIR="$HOME/refactoring-cli"
mkdir -p "$TMP_POM_DIR"

jar xf "$PLUGIN_JAR" \
  META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml

if [ ! -f META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml ]; then
  echo "FATAL: Could not extract pom.xml from plugin JAR."
  exit 1
fi

mkdir -p "$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli"
mv META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml \
   "$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml"

rm -rf META-INF

POM="$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml"

ECLIPSE_REPO_URL=$(grep -oPm1 "(?<=<eclipse.release.repo>)[^<]+" "$POM" || true)
ECLIPSE_VERSION="${ECLIPSE_REPO_URL##*/}"

if [ -z "$ECLIPSE_VERSION" ]; then
  echo "FATAL: Could not extract Eclipse version from pom.xml"
  exit 1
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

# Convert INPUT_CLEANUP_* → cleanup.x.y.z
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
# Assemble Eclipse arguments
# ------------------------------

ECLIPSE_ARGS=(
  -nosplash
  -application io.github.nbauma109.refactoring.cli.app
  --profile "$PROFILE_FILE"
  --source "$SOURCE_LEVEL"
)

if [ -n "$EXTRA_CLASSPATH" ]; then
  ECLIPSE_ARGS+=( --classpath "$EXTRA_CLASSPATH" )
fi

ECLIPSE_ARGS+=( "$PROJECT_ROOT" )

# ------------------------------
# Launch Eclipse
# ------------------------------

echo "Running Eclipse cleanup..."
set +e
"$ECLIPSE_HOME/eclipse" "${ECLIPSE_ARGS[@]}"
EXIT_CODE=$?
set -e

echo "Eclipse exited with code $EXIT_CODE"

# ------------------------------
# Display log files on failure
# ------------------------------

echo "=========== ECLIPSE LOG OUTPUT ==========="
LOG_DIR="$ECLIPSE_HOME/configuration"

echo "Log directory: $LOG_DIR"
ls -al "$LOG_DIR"

LATEST_LOG=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1 || true)

if [ -n "$LATEST_LOG" ]; then
  echo "Showing latest log: $LATEST_LOG"
  echo "------------------------------------"
  cat "$LATEST_LOG"
else
  echo "No log files found."
fi

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "ERROR: Eclipse terminated with failure."
  exit "$EXIT_CODE"
fi

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

