---
description: Translate locale files for a target language using git diff workflow
argument-hint: <lang-code>
allowed-tools: Bash(git diff:*), Bash(cp:*), Bash(pnpm run locale:validate:*), Bash(ls:*), Bash(cat:*), Read, Edit, Write, Glob
---

# Create New Language Translation

Uses the `saas-translator` skill.

## Pre-Flight Check

First, detect if this repo has its own translation protocol:

```bash
# Check for established translation workflow
ls locales/TRANSLATION_PROTOCOL.md 2>/dev/null && echo "PROTOCOL_FOUND"
```

**If `PROTOCOL_FOUND`**: This repo has a structured translation workflow. Read and follow `locales/TRANSLATION_PROTOCOL.md` instead of the generic workflow below.

Otherwise, continue with the generic workflow below.

## Detect Locale Structure

```bash
# Modern structure (flat keys with text field)
ls locales/content/en/*.json 2>/dev/null && echo "MODERN_STRUCTURE"

# Legacy structure
ls src/locales/en/*.json 2>/dev/null && echo "LEGACY_STRUCTURE"
```

Set paths based on detection:
- **Modern**: `./locales/content/{lang}/`, guide at `locales/guides/for-translators/{lang}.md`
- **Legacy**: `src/locales/{lang}/`, guide at `src/locales/{lang}/export-guide.md`

**Paths to IGNORE** (do not edit): `./generate/`, `./src/locales/` — compiled/legacy, not source

## Workflow

1. **Get the diff** between English source and target locale:
   ```bash
   # Modern structure
   git diff --no-index locales/content/en locales/content/{lang} 2>/dev/null || echo "New locale"

   # Legacy structure
   git diff --no-index src/locales/en src/locales/{lang} 2>/dev/null || echo "New locale"
   ```

2. **Process file by file**, translating new/changed keys from English

3. **Reference the locale's export-guide** for language-specific rules (terminology, formality, formatting)

4. **Preserve**: `{{variables}}`, HTML tags, special characters

5. **Validate** if available: `pnpm run locale:validate {lang}`

## For New Languages

1. Copy English structure to target language directory
2. Read the export-guide for language-specific conventions (do not edit the guide)
3. Translate each JSON file, following export-guide rules

## For Multiple Locales in Parallel

Use `/d:translate-parallel-agents` to orchestrate multiple `saas-translator` background agents translating different locales simultaneously. This is more efficient for batch translation work.
