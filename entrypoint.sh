#!/bin/bash
set -euo pipefail

ECLIPSE_VERSION="$1"
ECLIPSE_PACKAGE="$2"
PROFILE="$3"
PROJECT_ROOT="$4"
SOURCE_LEVEL="$5"
EXTRA_CLASSPATH="${6:-}"
CLEANUP_OPTIONS_JSON="$7"

echo "Downloading Eclipse..."
eclipse-download "$ECLIPSE_VERSION" "$ECLIPSE_PACKAGE"

ECLIPSE_HOME=$(cat /opt/eclipse_home)

echo "Installing plugin into dropins..."
mkdir -p "$ECLIPSE_HOME/dropins/refactoring-cli"
cp /opt/io.github.nbauma109.refactoring.cli-1.0.0.jar "$ECLIPSE_HOME/dropins/refactoring-cli/"

CMD=(
  "$ECLIPSE_HOME/eclipse"
  -nosplash
  -application io.github.nbauma109.refactoring.cli.app
  --profile "$PROFILE"
  --source "$SOURCE_LEVEL"
  --cleanup-options "$CLEANUP_OPTIONS_JSON"
)

if [ -n "$EXTRA_CLASSPATH" ]; then
  CMD+=( --classpath "$EXTRA_CLASSPATH" )
fi

CMD+=( "$PROJECT_ROOT" )

echo "Running cleanup with command:"
printf ' %q' "${CMD[@]}"
echo

exec "${CMD[@]}"
