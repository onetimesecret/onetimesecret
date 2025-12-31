#!/usr/bin/env bash
#
# claude-translate-locale.sh - Translate a single locale using Claude CLI
#
# Usage:
#   ./src/scripts/locales/translate/claude-translate-locale.sh LOCALE [OPTIONS]
#
# Examples:
#   ./src/scripts/locales/translate/claude-translate-locale.sh pt_PT
#   ./src/scripts/locales/translate/claude-translate-locale.sh ru --dry-run
#   ./src/scripts/locales/translate/claude-translate-locale.sh de_AT --no-commit
#
# Options:
#   --dry-run     Preview changes without modifying files or calling Claude
#   --no-commit   Apply translations but skip the git commit step
#
# Prerequisites:
#   - Claude CLI installed and authenticated (`claude --version`)
#   - Python 3 for harmonize script and JSON processing
#
# Process:
#   1. Harmonize locale (copies English placeholders for missing keys)
#   2. Extract git diff of changed strings only
#   3. Load locale's export-guide.md for translation context
#   4. Send diff to Claude CLI for translation (isolated session)
#   5. Parse Claude's JSON output and apply to locale files
#   6. Validate JSON syntax
#   7. Commit changes with [#I18N] prefix
#
# Notes:
#   - Each invocation is a fresh Claude session (no cross-locale contamination)
#   - Only translates strings in the diff, not the entire file
#   - Preserves all variables: {time}, {count}, {0}, {{var}}, etc.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOCALES_DIR="$PROJECT_ROOT/src/locales"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 LOCALE [--dry-run] [--no-commit]"
    echo ""
    echo "Arguments:"
    echo "  LOCALE      Locale code (e.g., pt_PT, ru, de_AT)"
    echo ""
    echo "Options:"
    echo "  --dry-run   Preview without modifying files or calling Claude"
    echo "  --no-commit Apply translations but skip git commit"
    echo ""
    echo "Available locales:"
    ls -1 "$LOCALES_DIR" 2>/dev/null | grep -v '^en$' | grep -v '\.md$' | tr '\n' ' '
    echo ""
    exit 1
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
LOCALE=""
DRY_RUN=false
NO_COMMIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --no-commit) NO_COMMIT=true; shift ;;
        -h|--help) usage ;;
        *) LOCALE="$1"; shift ;;
    esac
done

[[ -z "$LOCALE" ]] && usage

# Validate locale exists
if [[ ! -d "$LOCALES_DIR/$LOCALE" ]]; then
    log_error "Locale directory not found: $LOCALES_DIR/$LOCALE"
    exit 1
fi

# Check for export-guide.md
EXPORT_GUIDE="$LOCALES_DIR/$LOCALE/export-guide.md"
if [[ ! -f "$EXPORT_GUIDE" ]]; then
    log_warn "No export-guide.md found for $LOCALE - translations may be less accurate"
    EXPORT_GUIDE=""
fi

log_info "Starting translation for locale: $LOCALE"

# Step 1: Harmonize locale (copy English for missing keys)
log_info "Step 1: Harmonizing locale files..."
if [[ "$DRY_RUN" == "false" ]]; then
    python3 "$SCRIPT_DIR/../harmonize/harmonize-locale-file.py" -c "$LOCALE"
else
    log_info "[DRY-RUN] Would run: harmonize-locale-file.py -c $LOCALE"
fi

# Step 2: Check if there are changes to translate
CHANGED_FILES=$(git -C "$PROJECT_ROOT" diff --name-only "src/locales/$LOCALE/" 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
    log_info "No changes detected for $LOCALE - already up to date"
    exit 0
fi

log_info "Changed files:"
echo "$CHANGED_FILES" | sed 's/^/  /'

# Step 3: Generate the diff for Claude
DIFF_OUTPUT=$(git -C "$PROJECT_ROOT" diff "src/locales/$LOCALE/")
DIFF_LINES=$(echo "$DIFF_OUTPUT" | wc -l)
log_info "Diff contains $DIFF_LINES lines of changes"

# Step 4: Build the Claude prompt
PROMPT_FILE=$(mktemp)
trap "rm -f $PROMPT_FILE" EXIT

cat > "$PROMPT_FILE" << 'PROMPT_HEADER'
You are translating locale files for OneTime Secret, a secure message sharing service.

## Your Task
Translate the English placeholder strings shown in the git diff below into the target language.
Only translate strings that were added (lines starting with +).
Preserve all variables exactly: {time}, {count}, {limit}, {0}, {1}, {{var}}, etc.

## Critical Rules
1. PRESERVE ALL VARIABLES EXACTLY - {time} must stay {time}, not {Zeit} or {tiempo}
2. Keep HTML tags intact: <a>, <strong>, <br>, etc.
3. Maintain the same JSON structure
4. Use terminology from the export-guide.md if provided
5. For "secret" - use the culturally appropriate term (not always literal translation)
6. Distinguish: password (account login) vs passphrase (protects individual secrets)
7. DO NOT translate keys starting with underscore (_README, _context, etc.) - keep in English
8. Security messages must remain generic per OWASP guidelines

## Output Format
For each file, output the corrected JSON content for ONLY the keys that need translation.
Use this format:

### FILE: path/to/file.json
```json
{
  "key.path.here": "Translated value",
  "another.key": "Another translation"
}
```

PROMPT_HEADER

# Add locales README for general guidelines
LOCALES_README="$LOCALES_DIR/README.md"
if [[ -f "$LOCALES_README" ]]; then
    echo "" >> "$PROMPT_FILE"
    echo "## Translation Guidelines (from README.md)" >> "$PROMPT_FILE"
    echo '```markdown' >> "$PROMPT_FILE"
    cat "$LOCALES_README" >> "$PROMPT_FILE"
    echo '```' >> "$PROMPT_FILE"
fi

# Add export guide if available
if [[ -n "$EXPORT_GUIDE" ]]; then
    echo "" >> "$PROMPT_FILE"
    echo "## Export Guide for $LOCALE" >> "$PROMPT_FILE"
    echo '```markdown' >> "$PROMPT_FILE"
    cat "$EXPORT_GUIDE" >> "$PROMPT_FILE"
    echo '```' >> "$PROMPT_FILE"
fi

# Add the diff
cat >> "$PROMPT_FILE" << DIFF_SECTION

## Git Diff to Translate
Target locale: $LOCALE

\`\`\`diff
$DIFF_OUTPUT
\`\`\`

Now translate the added English strings (+ lines) into $LOCALE. Output ONLY the translations needed.
DIFF_SECTION

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would send to Claude:"
    echo "---"
    head -50 "$PROMPT_FILE"
    echo "... (truncated, $DIFF_LINES lines of diff)"
    echo "---"
    exit 0
fi

# Step 5: Call Claude CLI
log_info "Step 2: Sending to Claude for translation..."
CLAUDE_OUTPUT=$(mktemp)

# Use claude CLI with the prompt
# --print outputs just the response, --dangerously-skip-permissions for automation
cd "$PROJECT_ROOT"
claude --print --dangerously-skip-permissions < "$PROMPT_FILE" > "$CLAUDE_OUTPUT" 2>&1 || {
    log_error "Claude CLI failed. Output:"
    cat "$CLAUDE_OUTPUT"
    rm -f "$CLAUDE_OUTPUT"
    exit 1
}

log_info "Claude response received ($(wc -l < "$CLAUDE_OUTPUT") lines)"

# Step 6: Apply translations
log_info "Step 3: Applying translations..."

# Parse Claude's output and apply to files
# This is a simplified approach - Claude outputs JSON blocks per file
python3 << APPLY_SCRIPT
import json
import re
import sys
from pathlib import Path

output_file = "$CLAUDE_OUTPUT"
locales_dir = Path("$LOCALES_DIR")
locale = "$LOCALE"

with open(output_file) as f:
    content = f.read()

# Find all FILE: markers and their JSON blocks
pattern = r'### FILE:\s*(.+?\.json)\s*\n\`\`\`json\s*\n(.*?)\n\`\`\`'
matches = re.findall(pattern, content, re.DOTALL)

if not matches:
    print("No translation blocks found in Claude output")
    print("Raw output preview:")
    print(content[:500])
    sys.exit(1)

for filepath, json_block in matches:
    # Normalize filepath
    if filepath.startswith('src/locales/'):
        filepath = filepath.replace('src/locales/', '')

    target_file = locales_dir / locale / Path(filepath).name

    if not target_file.exists():
        print(f"Warning: Target file not found: {target_file}")
        continue

    try:
        translations = json.loads(json_block)
    except json.JSONDecodeError as e:
        print(f"Warning: Invalid JSON for {filepath}: {e}")
        continue

    # Load existing file
    with open(target_file, 'r', encoding='utf-8') as f:
        existing = json.load(f)

    # Apply translations (handles nested keys like "web.secrets.key")
    def set_nested(obj, key_path, value):
        keys = key_path.split('.')
        for key in keys[:-1]:
            obj = obj.setdefault(key, {})
        obj[keys[-1]] = value

    updated = 0
    for key, value in translations.items():
        try:
            set_nested(existing, key, value)
            updated += 1
        except Exception as e:
            print(f"Warning: Could not set {key}: {e}")

    # Write back
    with open(target_file, 'w', encoding='utf-8') as f:
        json.dump(existing, f, ensure_ascii=False, indent=2)
        f.write('\n')

    print(f"Updated {target_file.name}: {updated} translations")

print("Done applying translations")
APPLY_SCRIPT

rm -f "$CLAUDE_OUTPUT"

# Step 7: Validate JSON
log_info "Step 4: Validating JSON..."
VALIDATION_FAILED=false
for file in "$LOCALES_DIR/$LOCALE"/*.json; do
    if ! python3 -m json.tool "$file" > /dev/null 2>&1; then
        log_error "Invalid JSON: $file"
        VALIDATION_FAILED=true
    fi
done

if [[ "$VALIDATION_FAILED" == "true" ]]; then
    log_error "JSON validation failed - not committing"
    exit 1
fi
log_info "All JSON files valid"

# Step 8: Commit
if [[ "$NO_COMMIT" == "false" ]]; then
    log_info "Step 5: Committing changes..."
    cd "$PROJECT_ROOT"
    git add "src/locales/$LOCALE/"
    git commit -m "[#I18N] i18n($LOCALE): Translate harmonized locale files

Automated translation of new/missing keys using Claude.
" || {
        log_warn "Nothing to commit (no changes)"
    }
    log_info "Committed changes for $LOCALE"
else
    log_info "[NO-COMMIT] Skipping commit step"
fi

log_info "Translation complete for $LOCALE"
echo ""
echo "Review changes with: git diff HEAD~1 src/locales/$LOCALE/"
