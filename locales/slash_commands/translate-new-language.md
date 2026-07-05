---
description: Translate locale files for a single target language using git diff detection, routed through the agent protocol
argument-hint: <lang-code>
allowed-tools: Bash(git diff:*), Bash(cp:*), Bash(ls:*), Bash(cat:*), Bash([ -f:*), Bash(jq:*), Bash(python3 locales/scripts/i18n tasks:*), Task, Read, Glob
---

# Translate a Single Language

Orchestration ONLY. This command detects what needs translating for one language,
then routes the actual translation work to a `saas-translator` agent that follows
`locales/AGENT_TRANSLATION_PROTOCOL.md` exactly and reads its per-locale governance
from `generated/i18n/.resolved/{LANG}.json` (derived on demand). It carries no
per-locale convention prose.

**Prerequisite (resolved-only, no-vendor): governance exists upstream first.**
A language becomes translatable only once the derive produces
`generated/i18n/.resolved/{LANG}.json` with a populated register + glossary.
"New language" here means *new to translation* — its governance already exists,
its content just hasn't been drained yet. This command does **not** bootstrap a
language from nothing: if the derived artifact is missing, add the language's
governance in the `translation-rules` repo
(`_references/authoring/backfill-locale.md`), bump the pin in
`.github/workflows/resolved-derive-gate.yml`, and re-derive
(`locales/scripts/derive-governance.sh`) first. The gate below enforces that
ordering rather than silently producing ungoverned translations.

## Detect Locale Structure

```bash
ls locales/content/en/*.json 2>/dev/null && echo "MODERN_STRUCTURE"
```

Source of truth is `./locales/content/{lang}/`.

**Paths to IGNORE** (do not edit): `./generate/`, `./src/locales/` — compiled/legacy, not source.

## Eligibility gate

**Preflight — derive governance (no-vendor).** Governance is not committed; derive
it on demand into the gitignored `generated/i18n/` cache first:

```bash
locales/scripts/derive-governance.sh   # writes generated/i18n/.resolved/<loc>.json at the canonical pin
```

A language is eligible for automated drain **only if**
`generated/i18n/.resolved/{LANG}.json` exists with a populated `register` and a
populated `glossary` (i.e., it is governed upstream at the pin). Check it first and
**SKIP + warn** if it is missing:

```bash
if [ -f "generated/i18n/.resolved/$LANG.json" ] \
   && jq -e '((.register // {}) | length > 0) and ((.glossary // {}) | length > 0)' "generated/i18n/.resolved/$LANG.json" >/dev/null 2>&1; then
  echo "ELIGIBLE: $LANG"
else
  echo "SKIP (not governed at pin): $LANG — add it in translation-rules and bump the pin, then re-derive"
fi
```

If not eligible, stop and report — do not translate without the resolved artifact.

## Detection / diff flow

1. **Get the diff** between English source and the target language to scope the
   new/changed keys:
   ```bash
   git diff --no-index locales/content/en locales/content/{lang} 2>/dev/null || echo "New locale"
   ```

2. **For a brand-new language**, seed the directory from English structure so the
   keys exist to be drained:
   ```bash
   cp -r locales/content/en locales/content/{lang}
   ```

3. **Build the task queue** so the agent has pending work:
   ```bash
   python3 locales/scripts/i18n tasks create {lang}
   python3 locales/scripts/i18n tasks next {lang} --stats
   ```

## Route the translation to an agent

Launch a `saas-translator` agent with a short prompt — workflow and governance live
in the referenced files:

```
Task tool:
  description: "Translate {LANG}"
  subagent_type: "saas-translator"
  prompt: |
    Drain translation tasks for locale {LANG}. Follow
    locales/AGENT_TRANSLATION_PROTOCOL.md exactly. Per-locale governance
    (register, glossary, binding rules, declined decisions):
    generated/i18n/.resolved/{LANG}.json. Preserve all interpolation/markup tokens;
    brand names stay English. Loop until 0 pending; do not export or commit.
```

## Done

DONE = `python3 locales/scripts/i18n tasks next {lang} --stats` shows 0 pending.
Verify, then report. Do NOT export or commit — that's a separate human step.

## For Multiple Locales in Parallel

Use `/d:translate-parallel-agents` to orchestrate multiple `saas-translator`
background agents translating different locales simultaneously. This is more
efficient for batch translation work.
