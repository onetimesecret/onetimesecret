---
description: Translate locale files for a single target language using git diff detection, routed through the agent protocol
argument-hint: <lang-code>
allowed-tools: Bash(git diff:*), Bash(cp:*), Bash(ls:*), Bash(cat:*), Bash([ -f:*), Bash(jq:*), Bash(python3 locales/scripts/i18n tasks:*), Task, Read, Glob
---

# Translate a Single Language

Orchestration ONLY. This command detects what needs translating for one language,
then routes the actual translation work to a `saas-translator` agent that follows
`locales/AGENT_TRANSLATION_PROTOCOL.md` exactly and reads its per-locale governance
from `locales/.resolved/{LANG}.json`. It carries no per-locale convention prose.

## Detect Locale Structure

```bash
ls locales/content/en/*.json 2>/dev/null && echo "MODERN_STRUCTURE"
```

Source of truth is `./locales/content/{lang}/`.

**Paths to IGNORE** (do not edit): `./generate/`, `./src/locales/` — compiled/legacy, not source.

## Eligibility gate

A language is eligible for automated drain **only if**
`locales/.resolved/{LANG}.json` exists with a populated `register` and a populated
`glossary` (i.e., its governance has been back-ported upstream). Check it first and
**SKIP + warn** if it is missing:

```bash
if [ -f "locales/.resolved/$LANG.json" ] \
   && jq -e '((.register // {}) | length > 0) and ((.glossary // {}) | length > 0)' "locales/.resolved/$LANG.json" >/dev/null 2>&1; then
  echo "ELIGIBLE: $LANG"
else
  echo "SKIP (no resolved governance): $LANG — back-port locales/.resolved/$LANG.json first"
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
    locales/.resolved/{LANG}.json. Preserve all interpolation/markup tokens;
    brand names stay English. Loop until 0 pending; do not export or commit.
```

## Done

DONE = `python3 locales/scripts/i18n tasks next {lang} --stats` shows 0 pending.
Verify, then report. Do NOT export or commit — that's a separate human step.

## For Multiple Locales in Parallel

Use `/d:translate-parallel-agents` to orchestrate multiple `saas-translator`
background agents translating different locales simultaneously. This is more
efficient for batch translation work.
