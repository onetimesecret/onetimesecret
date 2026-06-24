# Review Locale Branches

Reviews `i18n/update-*` branches by language family using parallel code-reviewer agents.

## Workflow

### Stage 1: Automated Validation (run first)

This stage is pure deterministic mechanics — it lives in the checked-in script,
not in this prompt. Run variable validation across all `i18n/update-*` branches:

```bash
bash locales/scripts/review-locale-branches.sh validate
```

For each branch it runs `python3 locales/scripts/i18n validate variables --json
--locale <locale>`, writes the JSON to `/tmp/i18n-validate-{locale}.json` (pass a
`RESULTS_DIR` argument to override), and prints one line per locale with a
mismatch count > 0. It always exits 0 — it's a report, not a gate.

Output is deterministic: a locale only appears if it has `N > 0` errors to fix.
View details with `jq . /tmp/i18n-validate-{locale}.json`.

**Why `--json`:** The `--summary` flag outputs bare numbers that are easy to misinterpret. JSON output is unambiguous and includes full issue details for fixing.

### Stage 2: Agent Review by Language Family

Launch up to 5-6 `code-reviewer` agents in parallel, grouped by language family.
The table below is for human readability; the authoritative mapping lives in the
script — print it with `bash locales/scripts/review-locale-branches.sh families`:

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
# Timestamp to the minute so multiple review runs on the same day land in
# distinct directories instead of overwriting each other.
REVIEW_DATE=$(date +%Y-%m-%d-%H%M)
REVIEW_DIR="locales/reviews/${REVIEW_DATE}"
bash locales/scripts/review-locale-branches.sh init "$REVIEW_DIR"
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

This stage is pure deterministic mechanics — it lives in the checked-in script.
After all agents complete, build the per-family group summary files:

```bash
bash locales/scripts/review-locale-branches.sh consolidate "$REVIEW_DIR"
```

For each family group it writes `${REVIEW_DIR}/${group}.md` by concatenating the
per-locale `${REVIEW_DIR}/${loc}.md` files that exist, with a header and `---`
separators. The family->locales mapping comes from the script's authoritative
table (see `review-locale-branches.sh families`).

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
