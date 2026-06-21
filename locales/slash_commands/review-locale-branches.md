# Review Locale Branches

Reviews `i18n/update-*` branches by language family using parallel code-reviewer agents.

## Workflow

### Stage 1: Automated Validation (run first)

Run variable validation with `--json` for deterministic, machine-readable output:

```bash
for branch in $(git branch --list 'i18n/update-*' | tr -d ' ' | sed 's/\x1b\[[0-9;]*m//g'); do
  locale=${branch#i18n/update-}
  python3 locales/scripts/i18n validate variables --json --locale "$locale" > "/tmp/i18n-validate-${locale}.json"
  count=$(jq '.summary | to_entries | map(.value) | add // 0' "/tmp/i18n-validate-${locale}.json")
  if [ "$count" -gt 0 ]; then
    echo "$locale: $count variable mismatches — /tmp/i18n-validate-${locale}.json"
  fi
done
```

Output is deterministic: `0` = clean, `N` = errors to fix. View details with `jq . /tmp/i18n-validate-{locale}.json`.

**Why `--json`:** The `--summary` flag outputs bare numbers that are easy to misinterpret. JSON output is unambiguous and includes full issue details for fixing.

### Stage 2: Agent Review by Language Family

Launch up to 5-6 `code-reviewer` agents in parallel, grouped by language family:

| Family | Locales |
|--------|---------|
| semitic-rtl | ar, he |
| slavic | bg, cs, pl, ru, sl_SI, uk |
| germanic | de, de_AT, nl, sv_SE |
| romance | ca_ES, es, fr_CA, fr_FR, it_IT, pt_BR, pt_PT |
| cjk | ja, ko, zh |
| other | da_DK, el_GR, eo, hu, mi_NZ, tr, vi |

**Output structure:**

```
locales/reviews/{DATE}/
├── {locale}.md          # Per-locale review (one per agent)
├── semitic-rtl.md       # Group summary (ar, he)
├── slavic.md            # Group summary (bg, cs, pl, ru, sl_SI, uk)
├── germanic.md          # ...
├── romance.md
├── cjk.md
└── other.md
```

Create the output directory before launching agents:

```bash
REVIEW_DATE=$(date +%Y-%m-%d)
REVIEW_DIR="locales/reviews/${REVIEW_DATE}"
mkdir -p "$REVIEW_DIR"
```

For each agent, use `subagent_type: "feature-dev:code-reviewer"` with `run_in_background: true`.

**Agent prompt template:**

```
Review i18n/update-{LOCALE} branch for translation quality.

Context: This branch contains {LOCALE} ({LANGUAGE}) translations exported from the task DB.

Steps:
1. git diff develop...i18n/update-{LOCALE} -- locales/content/{LOCALE}/
2. Spot-check 3-5 files for:
   - Variable preservation: {var}, {{var}}, %{var}, %s, <tag> must match English
   - Brand consistency: "Onetime Secret" unchanged
   - Empty/placeholder values
   - Encoding issues (UTF-8)
3. For {LANGUAGE_FAMILY} languages, also check:
   {FAMILY_SPECIFIC_CHECKS}

Write your review to: locales/reviews/{DATE}/{LOCALE}.md

Format:
# {LOCALE} Review - {DATE}

## Summary
[1-2 sentences]

## Critical (must fix)
- [issue] or "None"

## Warning (should review)
- [issue] or "None"

## Info
- [observations] or "None"
```

**Family-specific checks:**
- RTL (ar, he): bidirectional text markers, RTL punctuation
- CJK (ja, ko, zh): no spurious spaces, character encoding
- Slavic: grammatical cases preserved in templates
- Romance: apostrophes/accents not escaped

### Stage 3: Consolidate Group Reviews

After all agents complete, create group summary files:

```bash
for group in semitic-rtl slavic germanic cjk romance other; do
  # Map group to locales (from table above)
  case $group in
    semitic-rtl) locales="ar he" ;;
    slavic) locales="bg cs pl ru sl_SI uk" ;;
    germanic) locales="de de_AT nl sv_SE" ;;
    romance) locales="ca_ES es fr_CA fr_FR it_IT pt_BR pt_PT" ;;
    cjk) locales="ja ko zh" ;;
    other) locales="da_DK el_GR eo hu mi_NZ tr vi" ;;
  esac

  echo "# ${group} Group Review - ${REVIEW_DATE}" > "${REVIEW_DIR}/${group}.md"
  echo "" >> "${REVIEW_DIR}/${group}.md"
  echo "Locales: ${locales}" >> "${REVIEW_DIR}/${group}.md"
  echo "" >> "${REVIEW_DIR}/${group}.md"

  for loc in $locales; do
    if [ -f "${REVIEW_DIR}/${loc}.md" ]; then
      echo "---" >> "${REVIEW_DIR}/${group}.md"
      cat "${REVIEW_DIR}/${loc}.md" >> "${REVIEW_DIR}/${group}.md"
      echo "" >> "${REVIEW_DIR}/${group}.md"
    fi
  done
done
```

### Stage 4: Triage and Fix

After consolidation:
1. Review group files for Critical findings — must fix before merge
2. Review Warnings — decide case-by-case
3. Apply fixes to branches as needed
4. Re-run Stage 1 validation on fixed branches
5. Commit reviews to repo: `git add locales/reviews/ && git commit -m "i18n: add ${REVIEW_DATE} translation reviews"`

## Usage

```
/d:review-locale-branches
```

The orchestrator will:
1. List all `i18n/update-*` branches
2. Run Stage 1 validation
3. Launch Stage 2 agents (5-6 at a time)
4. Report consolidated findings
