#!/bin/bash
#
# Generate translation template from harmonization changes
#

set -e

# Show usage information
show_usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -o, --output DIR    Output directory for templates (default: ./translation-templates)"
  echo "  -h, --help          Show this help message"
  echo ""
  echo "This script generates translation templates for locale files that have been"
  echo "modified by the harmonization process. It creates JSON templates containing"
  echo "only the keys that need translation."
  echo ""
  echo "Requirements:"
  echo "  - Must be run from project root directory"
  echo "  - Requires jq to be installed"
  echo "  - Works with git diff to detect changed locale files"
}

check_requirements() {
  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    echo "Please install jq: https://stedolan.github.io/jq/download/"
    exit 1
  fi

  # Check if we're in a git repository
  if ! git rev-parse --git-dir &> /dev/null; then
    echo "Error: This script must be run from within a git repository"
    exit 1
  fi

  # Check if src/locales/en.json exists
  if [[ ! -f "src/locales/en.json" ]]; then
    echo "Error: src/locales/en.json not found"
    echo "Please run this script from the project root directory"
    exit 1
  fi
}

generate_translation_template() {
  local output_dir="${1:-./translation-templates}"

  echo "Generating translation templates in: $output_dir"
  mkdir -p "$output_dir"

  # Get list of modified locale files
  local modified_locales=($(git diff --name-only | grep 'src/locales/' | grep -v 'en.json' || true))

  if [[ ${#modified_locales[@]} -eq 0 ]]; then
    echo "No modified locale files found. Nothing to generate."
    return 0
  fi

  echo "Found ${#modified_locales[@]} modified locale file(s):"
  printf "  - %s\n" "${modified_locales[@]}"
  echo ""

  # For each modified locale
  for locale_file in "${modified_locales[@]}"; do
    if [[ ! -f "$locale_file" ]]; then
      echo "Warning: Locale file $locale_file not found, skipping..."
      continue
    fi

    local locale=$(basename "$locale_file" .json)
    local template_file="$output_dir/$locale-translation-needed.json"

    echo "Generating template for $locale..."

    # Validate locale file is valid JSON
    if ! jq empty "$locale_file" 2>/dev/null; then
      echo "Warning: $locale_file contains invalid JSON, skipping..."
      continue
    fi

    # Create a JSON object with only the keys that need translation
    jq --tab '
      # Get the current locale content
      . as $current |

      # Get English content for reference
      (input | .) as $english |

      # Find keys where current value is empty string but English has content
      reduce (paths(scalars) as $path |
        if (getpath($path) == "" and ($english | getpath($path) != ""))
        then {($path | join(".")): ($english | getpath($path))}
        else empty
        end
      ) as $item ({}; . + $item)
    ' "$locale_file" src/locales/en.json > "$template_file"

    # Check if template has any keys
    local key_count=$(jq 'keys | length' "$template_file" 2>/dev/null || echo "0")

    if [[ "$key_count" -eq 0 ]]; then
      echo "  No keys need translation for $locale, removing empty template..."
      rm "$template_file"
      continue
    fi

    echo "  Generated $key_count translation keys for $locale"

    # Generate markdown report for this locale
    cat > "$output_dir/$locale-report.md" << EOF
# Translation Report: $locale

## Instructions
1. Translate the English phrases in the JSON template below
2. Keep the JSON structure intact - only change the values, not the keys
3. Ensure quotes and special characters are properly escaped
4. Submit translated JSON back to the project

## Translation Template
The following keys need translation:

\`\`\`json
$(cat "$template_file")
\`\`\`

## Key Summary
- **Total keys:** $key_count
- **Source locale:** English (en.json)
- **Target locale:** $locale
- **Template file:** $locale-translation-needed.json

## Integration
Once translated, use the apply-translations script:
\`\`\`bash
./src/locales/scripts/apply-translations.sh $locale-translation-needed.json $locale
\`\`\`

This will merge your translations back into \`src/locales/$locale.json\`
EOF
  done

  echo ""
  echo "Translation template generation complete!"
  echo "Templates saved to: $output_dir"
}

# Parse command line arguments
OUTPUT_DIR="./translation-templates"

while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1"
      echo ""
      show_usage
      exit 1
      ;;
  esac
done

# Main execution
check_requirements
generate_translation_template "$OUTPUT_DIR"
