#!/bin/bash
#
# Apply translations from template back to locale files
#

set -e

# Show usage information
show_usage() {
  echo "Usage: $0 <translation_file> <target_locale>"
  echo ""
  echo "Arguments:"
  echo "  translation_file  Path to JSON file containing translations"
  echo "  target_locale     Target locale code (e.g., 'fr', 'es', 'de')"
  echo ""
  echo "Example:"
  echo "  $0 fr-translation-needed.json fr"
  echo ""
  echo "The script will:"
  echo "  1. Backup the existing locale file"
  echo "  2. Merge translations into src/locales/\$target_locale.json"
  echo "  3. Validate the resulting JSON"
}

apply_translations() {
  local translation_file="$1"
  local target_locale="$2"
  local locale_file="src/locales/$target_locale.json"

  if [[ ! -f "$translation_file" ]]; then
    echo "Error: Translation file not found: $translation_file"
    exit 1
  fi

  if [[ ! -f "$locale_file" ]]; then
    echo "Error: Target locale file not found: $locale_file"
    exit 1
  fi

  echo "Applying translations from $translation_file to $locale_file..."

  # Create backup
  cp "$locale_file" "$locale_file.backup"
  echo "Created backup: $locale_file.backup"

  # Merge translations using jq
  jq --tab '
    . as $current |
    (input | .) as $translations |

    # For each translation, update the corresponding path
    reduce ($translations | to_entries[] | {key: .key, value: .value}) as $item (
      $current;
      setpath($item.key | split(".") | map(tonumber? // .); $item.value)
    )
  ' "$locale_file" "$translation_file" > "$locale_file.tmp"

  # Validate JSON and apply
  if jq empty "$locale_file.tmp" 2>/dev/null; then
    mv "$locale_file.tmp" "$locale_file"
    echo "Successfully applied translations to $locale_file"

    # Show summary of changes
    local translated_count=$(jq 'keys | length' "$translation_file" 2>/dev/null || echo "0")
    echo "Applied $translated_count translations"
  else
    echo "Error: Invalid JSON in translation file"
    rm "$locale_file.tmp"
    exit 1
  fi
}

# Main execution
if [[ $# -ne 2 ]]; then
  echo "Error: Incorrect number of arguments"
  echo ""
  show_usage
  exit 1
fi

# Check if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_usage
  exit 0
fi

# Execute the function with provided arguments
apply_translations "$1" "$2"
