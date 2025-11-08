#!/bin/bash

# Debug script to analyze locale file structure differences
#
# Usage: ./debug-locale-structure.sh [-q] [-f] [-v] LOCALE_FILE
# -q: quiet mode (suppress non-essential output)
# -f: filename only output for conflicts
# -v: verbose output
#
# Exit: 0 if no conflicts, 1 if conflicts found

QUIET=${QUIET:-0}
FILENAME_ONLY=${FILENAME_ONLY:-0}
VERBOSE=${VERBOSE:-0}
BASELOCALE=${BASELOCALE:-"en"}
BASEPATH=${BASEPATH:-"src/locales/${BASELOCALE}.json"}

while getopts ":qfv" opt; do
  case $opt in
    q) QUIET=1 ;;
    f) FILENAME_ONLY=1 ;;
    v) VERBOSE=1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND -1))

LOCALE="$1"
[ -z "$LOCALE" ] && echo "Usage: $0 [-q] [-f] [-v] LOCALE_FILE" >&2 && exit 1
[ ! -f "$LOCALE" ] && echo "File not found: $LOCALE" >&2 && exit 1
[ ! -f "$BASEPATH" ] && echo "Base file not found: $BASEPATH" >&2 && exit 1

# Skip if analyzing the base locale against itself
LOCALE_NAME=$(basename "$LOCALE" .json)
BASE_NAME=$(basename "$BASEPATH" .json)
if [ "$LOCALE_NAME" = "$BASE_NAME" ]; then
  [ $QUIET -eq 0 ] && echo "Skipping self-comparison for $LOCALE_NAME"
  exit 0
fi

# Function to check for structural conflicts
check_conflicts() {
  jq -n --slurpfile base "$BASEPATH" --slurpfile target "$LOCALE" '
    def find_conflicts($base; $target; $path):
      if ($base | type) == "object" and ($target | type) == "object" then
        ($base | keys[]) as $k |
        if $target | has($k) then
          find_conflicts($base[$k]; $target[$k]; $path + [$k])
        else
          empty
        end
      elif ($base | type) == "string" and ($target | type) == "object" then
        {
          path: ($path | join(".")),
          conflict: "base=string, target=object",
          base_value: $base,
          target_type: "object"
        }
      elif ($base | type) == "object" and ($target | type) == "string" then
        {
          path: ($path | join(".")),
          conflict: "base=object, target=string",
          base_type: "object",
          target_value: $target
        }
      else
        empty
      end;

    [find_conflicts($base[0]; $target[0]; [])]
  '
}

# Function to find missing keys
find_missing_keys() {
  jq -n --slurpfile base "$BASEPATH" --slurpfile target "$LOCALE" '
    def find_missing($base; $target; $path):
      if ($base | type) == "object" then
        ($base | keys[]) as $k |
        if $target | has($k) then
          if ($target[$k] | type) == "object" and ($base[$k] | type) == "object" then
            find_missing($base[$k]; $target[$k]; $path + [$k])
          else
            empty
          end
        else
          $path + [$k] | join(".")
        end
      else
        empty
      end;

    [find_missing($base[0]; $target[0]; [])]
  '
}

# Get conflicts and missing keys
CONFLICTS=$(check_conflicts)
MISSING_KEYS=$(find_missing_keys)

CONFLICT_COUNT=$(echo "$CONFLICTS" | jq 'length')
MISSING_COUNT=$(echo "$MISSING_KEYS" | jq 'length')
TOTAL_ISSUES=$((CONFLICT_COUNT + MISSING_COUNT))

# Handle filename-only output
if [ $FILENAME_ONLY -eq 1 ]; then
  if [ $TOTAL_ISSUES -gt 0 ]; then
    echo "$LOCALE"
    exit 1
  else
    exit 0
  fi
fi

# Handle quiet mode
if [ $QUIET -eq 1 ]; then
  [ $TOTAL_ISSUES -gt 0 ] && exit 1 || exit 0
fi

# Normal output
echo "=== Analyzing $(basename "$LOCALE") against $(basename "$BASEPATH") ==="

if [ $CONFLICT_COUNT -gt 0 ]; then
  echo "STRUCTURAL CONFLICTS ($CONFLICT_COUNT):"
  echo "$CONFLICTS" | jq -r '.[] | "  • \(.path): \(.conflict)"'

  if [ $VERBOSE -eq 1 ]; then
    echo
    echo "Conflict details:"
    echo "$CONFLICTS" | jq -r '.[] | "  \(.path):"
      + (if .base_value then "    Base value: \(.base_value)" else "    Base: \(.base_type)" end)
      + (if .target_value then "    Target value: \(.target_value)" else "    Target: \(.target_type)" end)'
  fi
fi

if [ $MISSING_COUNT -gt 0 ]; then
  [ $CONFLICT_COUNT -gt 0 ] && echo
  echo "MISSING KEYS ($MISSING_COUNT):"
  echo "$MISSING_KEYS" | jq -r '.[] | "  • " + .'
fi

if [ $TOTAL_ISSUES -eq 0 ]; then
  echo "✓ No structural conflicts found"
fi

echo
echo "Summary: $CONFLICT_COUNT conflicts, $MISSING_COUNT missing keys"

[ $TOTAL_ISSUES -gt 0 ] && exit 1 || exit 0
