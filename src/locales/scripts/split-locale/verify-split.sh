#!/usr/bin/env bash
#
# Locale Split Verification Script
#
# Uses jq to verify that split locale files can be recombined to match
# the original file exactly - no missing keys, no changed values.
#
# NOTE: When verification passes, any [diff-output-file] does not get created.
#
# Usage:
#   ./verify-split.sh <original-file> <split-directory> [diff-output-file]
#
# Examples:
#   ./verify-split.sh src/locales/en.json src/locales/en
#   ./verify-split.sh src/locales/en.json src/locales/en diff-output.txt
#
# This script:
# 1. Merges all JSON files from the split directory using jq
# 2. Compares the merged result with the original file
# 3. Reports any missing keys or changed values
# 4. Exits with status 0 if verification passes, 1 if it fails
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <original-file> <split-directory> [diff-output-file]"
  echo "Example: $0 src/locales/en.json src/locales/en"
  echo "         $0 src/locales/en.json src/locales/en diff.txt"
  exit 1
fi

ORIGINAL_FILE="$1"
SPLIT_DIR="$2"
DIFF_OUTPUT_FILE="${3:-}"

# Validate inputs
if [ ! -f "$ORIGINAL_FILE" ]; then
  echo -e "${RED}❌ Original file not found: $ORIGINAL_FILE${NC}"
  exit 1
fi

if [ ! -d "$SPLIT_DIR" ]; then
  echo -e "${RED}❌ Split directory not found: $SPLIT_DIR${NC}"
  exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ jq is not installed. Please install jq to use this script.${NC}"
  exit 1
fi

echo -e "${BLUE}🔍 Locale Split Verification${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Original file: ${YELLOW}$ORIGINAL_FILE${NC}"
echo -e "Split directory: ${YELLOW}$SPLIT_DIR${NC}"
echo ""

# Create temporary files
TEMP_DIR=$(mktemp -d)
MERGED_FILE="$TEMP_DIR/merged.json"
ORIGINAL_SORTED="$TEMP_DIR/original-sorted.json"
MERGED_SORTED="$TEMP_DIR/merged-sorted.json"

# Cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# Find all JSON files in split directory (excluding _debug and web.json)
# web.json is intermediate and should not be included in final merge
echo -e "${BLUE}📁 Finding split files...${NC}"
JSON_FILES=$(find "$SPLIT_DIR" -maxdepth 1 -name "*.json" -not -name "web.json" | sort)

if [ -z "$JSON_FILES" ]; then
  echo -e "${RED}❌ No JSON files found in $SPLIT_DIR${NC}"
  exit 1
fi

echo "Found files:"
echo "$JSON_FILES" | while read -r file; do
  echo "  - $(basename "$file")"
done
echo ""

# Merge all split files using jq
echo -e "${BLUE}🔄 Merging split files...${NC}"

# Start with an empty object
echo '{}' > "$MERGED_FILE"

# Merge each file into the result
for file in $JSON_FILES; do
  echo "  Merging $(basename "$file")..."
  jq -s '.[0] * .[1]' "$MERGED_FILE" "$file" > "$TEMP_DIR/temp.json"
  mv "$TEMP_DIR/temp.json" "$MERGED_FILE"
done

echo ""

# Sort both files for comparison (keys in alphabetical order, recursively)
echo -e "${BLUE}📊 Sorting JSON for comparison...${NC}"
jq --sort-keys '.' "$ORIGINAL_FILE" > "$ORIGINAL_SORTED"
jq --sort-keys '.' "$MERGED_FILE" > "$MERGED_SORTED"

# Compare files
echo -e "${BLUE}🔍 Comparing files...${NC}"
echo ""

if diff -q "$ORIGINAL_SORTED" "$MERGED_SORTED" > /dev/null 2>&1; then
  echo -e "${GREEN}✅ VERIFICATION PASSED!${NC}"
  echo ""
  echo "The split files can be recombined to exactly match the original file."
  echo "  ✓ All keys present"
  echo "  ✓ All values unchanged"
  echo ""
  exit 0
else
  echo -e "${RED}❌ VERIFICATION FAILED!${NC}"
  echo ""
  echo "The split files do not match the original file."
  echo ""

  # Show detailed differences
  echo -e "${YELLOW}Detailed differences:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Find missing keys (in original but not in merged)
  MISSING_KEYS=$(jq -r --slurpfile merged "$MERGED_SORTED" '
    . as $orig |
    ($merged[0] // {}) as $merged_data |

    # Flatten both objects to dot notation
    def flatten:
      . as $in |
      [ path(.. | select(type != "object" and type != "array")) ] as $paths |
      reduce $paths[] as $path (
        {};
        . + {($path | map(tostring) | join(".")): ($in | getpath($path))}
      );

    ($orig | flatten) as $orig_flat |
    ($merged_data | flatten) as $merged_flat |

    # Find keys in original but not in merged
    ($orig_flat | keys) - ($merged_flat | keys) | .[]
  ' "$ORIGINAL_SORTED")

  if [ -n "$MISSING_KEYS" ]; then
    echo -e "${RED}Missing keys (in original but not in merged):${NC}"
    echo "$MISSING_KEYS" | while read -r key; do
      echo "  - $key"
    done
    echo ""
  fi

  # Find extra keys (in merged but not in original)
  EXTRA_KEYS=$(jq -r --slurpfile merged "$MERGED_SORTED" '
    . as $orig |
    ($merged[0] // {}) as $merged_data |

    # Flatten both objects to dot notation
    def flatten:
      . as $in |
      [ path(.. | select(type != "object" and type != "array")) ] as $paths |
      reduce $paths[] as $path (
        {};
        . + {($path | map(tostring) | join(".")): ($in | getpath($path))}
      );

    ($orig | flatten) as $orig_flat |
    ($merged_data | flatten) as $merged_flat |

    # Find keys in merged but not in original
    ($merged_flat | keys) - ($orig_flat | keys) | .[]
  ' "$ORIGINAL_SORTED")

  if [ -n "$EXTRA_KEYS" ]; then
    echo -e "${RED}Extra keys (in merged but not in original):${NC}"
    echo "$EXTRA_KEYS" | while read -r key; do
      echo "  - $key"
    done
    echo ""
  fi

  # Find changed values
  CHANGED_VALUES=$(jq -r --slurpfile merged "$MERGED_SORTED" '
    . as $orig |
    ($merged[0] // {}) as $merged_data |

    # Flatten both objects to dot notation with values
    def flatten:
      . as $in |
      [ path(.. | select(type != "object" and type != "array")) ] as $paths |
      reduce $paths[] as $path (
        {};
        . + {($path | map(tostring) | join(".")): ($in | getpath($path))}
      );

    ($orig | flatten) as $orig_flat |
    ($merged_data | flatten) as $merged_flat |

    # Find keys with different values
    $orig_flat | keys[] | select($orig_flat[.] != $merged_flat[.])
  ' "$ORIGINAL_SORTED")

  if [ -n "$CHANGED_VALUES" ]; then
    echo -e "${RED}Changed values:${NC}"
    echo "$CHANGED_VALUES" | while read -r key; do
      echo "  Key: $key"
      ORIG_VAL=$(jq -r --arg key "$key" '
        def flatten:
          . as $in |
          [ path(.. | select(type != "object" and type != "array")) ] as $paths |
          reduce $paths[] as $path (
            {};
            . + {($path | map(tostring) | join(".")): ($in | getpath($path))}
          );
        flatten | .[$key]
      ' "$ORIGINAL_SORTED")
      MERGED_VAL=$(jq -r --arg key "$key" '
        def flatten:
          . as $in |
          [ path(.. | select(type != "object" and type != "array")) ] as $paths |
          reduce $paths[] as $path (
            {};
            . + {($path | map(tostring) | join(".")): ($in | getpath($path))}
          );
        flatten | .[$key]
      ' "$MERGED_SORTED")
      echo "    Original: $ORIG_VAL"
      echo "    Merged:   $MERGED_VAL"
      echo ""
    done
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  if [ -n "$DIFF_OUTPUT_FILE" ]; then
    echo "Saving full diff to: $DIFF_OUTPUT_FILE"
    diff -u "$ORIGINAL_SORTED" "$MERGED_SORTED" > "$DIFF_OUTPUT_FILE" || true
    echo "To view full diff, run:"
    echo "  less $DIFF_OUTPUT_FILE"
    echo ""
  else
    echo "Run with a third argument to save diff output:"
    echo "  $0 $ORIGINAL_FILE $SPLIT_DIR diff-output.txt"
    echo ""
  fi

  exit 1
fi
