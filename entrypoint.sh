#!/bin/bash
set -euo pipefail

# ------------------------------
# Read required inputs
# ------------------------------

PROJECT_ROOT="${INPUT_PROJECT_ROOT:-}"
SOURCE_LEVEL="${INPUT_SOURCE_LEVEL:-}"
EXTRA_CLASSPATH="${INPUT_EXTRA_CLASSPATH:-}"

if [ -z "$PROJECT_ROOT" ]; then
  echo "FATAL: INPUT_PROJECT_ROOT is required"
  exit 1
fi

if [ -z "$SOURCE_LEVEL" ]; then
  echo "FATAL: INPUT_SOURCE_LEVEL is required"
  exit 1
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

# Base directory for all temporary and generated files
BASE_DIR="$HOME/.refactoring-cli"
mkdir -p "$BASE_DIR"

WORKSPACE_DIR="$HOME/eclipse-workspace"
mkdir -p "$WORKSPACE_DIR"

# ------------------------------
# Extract pom.xml from plugin
# ------------------------------

PLUGIN_JAR="/opt/io.github.nbauma109.refactoring.cli-1.0.0.jar"

if [ ! -f "$PLUGIN_JAR" ]; then
  echo "FATAL: plugin JAR not found at $PLUGIN_JAR"
  exit 1
fi

TMP_POM_DIR="$BASE_DIR/pom"
rm -rf "$TMP_POM_DIR"
mkdir -p "$TMP_POM_DIR"

# Extract pom.xml in an isolated directory
pushd "$TMP_POM_DIR" >/dev/null

jar xf "$PLUGIN_JAR" \
  META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml

if [ ! -f META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml ]; then
  echo "FATAL: Could not extract pom.xml from plugin JAR."
  popd >/dev/null
  exit 1
fi

POM="$TMP_POM_DIR/META-INF/maven/io.github.nbauma109/io.github.nbauma109.refactoring.cli/pom.xml"

ECLIPSE_REPO_URL=$(grep -oPm1 "(?<=<eclipse.release.repo>)[^<]+" "$POM" || true)
ECLIPSE_VERSION="${ECLIPSE_REPO_URL##*/}"

popd >/dev/null
rm -rf "$TMP_POM_DIR"

if [ -z "$ECLIPSE_VERSION" ]; then
  echo "FATAL: Could not extract Eclipse version from pom.xml"
  exit 1
fi

echo "Using Eclipse release: $ECLIPSE_VERSION"

# ------------------------------
# Download Eclipse
# ------------------------------

eclipse-download "$ECLIPSE_VERSION" "java"

ECLIPSE_HOME=$(cat /opt/eclipse_home)

echo "Installing plugin JAR into $ECLIPSE_HOME/dropins/"
cp "$PLUGIN_JAR" "$ECLIPSE_HOME/dropins/"

# ------------------------------
# Generate cleanup XML profile
# ------------------------------

PROFILE_FILE="$BASE_DIR/cleanup-profile.xml"

cat > "$PROFILE_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<profiles version="2">
  <profile kind="CleanUpProfile" name="github-action" version="2">
EOF

# Convert INPUT_CLEANUP_* → cleanup.x.y.z entries
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

echo "Generated cleanup profile at $PROFILE_FILE:"
cat "$PROFILE_FILE"

# ------------------------------
# Launch Eclipse
# ------------------------------

echo "Starting Xvfb..."
XVFB_DISPLAY=":99"
Xvfb "$XVFB_DISPLAY" -screen 0 1920x1080x24 >$HOME/xvfb.log 2>&1 &
export DISPLAY="$XVFB_DISPLAY"

sleep 2

echo "Running Eclipse cleanup inside virtual display $DISPLAY..."

echo "Running Eclipse cleanup..."
set +e
"$ECLIPSE_HOME/eclipse" \
  -nosplash \
  -data "$WORKSPACE_DIR" \
  -application io.github.nbauma109.refactoring.cli.app \
  --profile "$PROFILE_FILE" \
  --source "$SOURCE_LEVEL" \
  ${EXTRA_CLASSPATH:+--classpath "$EXTRA_CLASSPATH"} \
  "$PROJECT_ROOT"
EXIT_CODE=$?
set -e

echo "Eclipse exited with code $EXIT_CODE"

# ------------------------------
# Display Eclipse configuration logs
# ------------------------------

echo "=========== ECLIPSE CONFIGURATION LOGS ==========="
LOG_DIR="$ECLIPSE_HOME/configuration"
echo "Configuration log directory: $LOG_DIR"

if [ -d "$LOG_DIR" ]; then
  ls -al "$LOG_DIR"
  LATEST_CONFIG_LOG=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1 || true)
  if [ -n "$LATEST_CONFIG_LOG" ]; then
    echo "Showing latest configuration log: $LATEST_CONFIG_LOG"
    echo "------------------------------------"
    cat "$LATEST_CONFIG_LOG"
  else
    echo "No configuration log files found."
  fi
else
  echo "Configuration directory does not exist: $LOG_DIR"
fi

# ------------------------------
# Display workspace log
# ------------------------------

echo "=========== ECLIPSE WORKSPACE LOG ==========="
WORKSPACE_LOG="$WORKSPACE_DIR/.metadata/.log"

echo "Workspace directory: $WORKSPACE_DIR"
if [ -f "$WORKSPACE_LOG" ]; then
  echo "Showing workspace log: $WORKSPACE_LOG"
  echo "------------------------------------"
  cat "$WORKSPACE_LOG"
else
  echo "No workspace log found at $WORKSPACE_LOG"
fi

# ------------------------------
# Propagate Eclipse exit code
# ------------------------------

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "ERROR: Eclipse terminated with failure."
  exit "$EXIT_CODE"
fi
