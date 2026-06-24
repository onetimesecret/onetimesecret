# Agent Translation Protocol

> **Audience: a single automated background translator agent draining one
> locale.** This is the machine-executable spec the orchestration slash commands
> (`/d:translate-parallel-agents`, `/d:start-translation-session`,
> `/d:translate-workflow`) point their `saas-translator` agents at. It is
> self-contained and executable by reference: an agent given a locale and this
> file has everything it needs to drain that locale's task queue.
>
> **Human-driven, conversational sessions follow a different file.** The manual
> session — claim/accept/skip/quit, glossary decisions, the QC protocol, and
> manual export/commit — lives in
> [`TRANSLATION_PROTOCOL.md`](./TRANSLATION_PROTOCOL.md). Do not run those human
> steps here.

## Scope

One agent, one locale, one job: translate every pending value and write it back
to the task DB, then stop. The agent does **not** export, sync, commit, create
branches, or record glossary decisions — those are human steps in
`TRANSLATION_PROTOCOL.md`.

Run everything from the repo root. The scripts need no environment setup (the
project uses direnv via `.envrc`; there is no `source .env.sh`).

## Precondition: resolved governance artifact required

A locale is in the agent-drain set **only once** `locales/.resolved/<LOCALE>.json`
exists with a populated `register` and a populated `glossary`. That file is the
resolved governance artifact — the single source of per-locale guidance for
automated drain. If it is missing or those fields are empty, the locale is **out
of scope** for automated drain until the governance is back-ported upstream;
skip it.

Agents read guidance from `locales/.resolved/<LOCALE>.json` and **only** from
there. Do **not** read `locales/guides/for-translators/*.md` — those are human
guides, not the resolved artifact.

`locales/.resolved/<LOCALE>.json` carries:

- **`register`** — form/pronoun choice, formality, and `forbidden_tokens` the
  locale must never emit.
- **`glossary`** — agreed term senses with examples; the binding rendering for
  recurring domain/brand terms.
- **binding rules** — constraints that must hold for every translation.
- **declined decisions** — choices that were considered and rejected; do not
  reintroduce them.

## Per-task cycle (one writer per locale, claim-free)

Loop this until the queue is dry:

1. **Get the next task** as JSON:
   ```bash
   python3 locales/scripts/i18n tasks next <LOCALE> --json
   ```
   Stop when there is no pending task. There is **one writer per locale**, so
   `tasks next` (which returns only *pending* rows) advances with zero orphans —
   do **not** use `--claim`.

2. **Translate every value** in the task using the guidance from
   `locales/.resolved/<LOCALE>.json`.

3. **Write the result object** — a flat `{"key": "translation"}` map whose key
   set is the **EXACT source key set** (none added, none dropped) — to a
   per-locale temp file with the Write tool:
   ```
   /tmp/trans_<LOCALE>.json
   ```
   Per-locale paths keep concurrent agents from clobbering each other. Use a
   file, not inline JSON: apostrophes and quotes (common in fr/es/it) break
   shell single-quoting and HEREDOCs.

4. **Save it back** with validation:
   ```bash
   python3 locales/scripts/i18n tasks update <ID> --file /tmp/trans_<LOCALE>.json --validate
   ```

5. **Read the output.** `--validate` is **advisory**: it warns on missing/extra
   keys but still saves and still exits 0 — it does **not** block a bad write. On
   any `Warning:` line (e.g. "Missing keys" / "Extra keys"), rebuild the object
   with the exact source key set and re-run the update. A completed row's key set
   must match the source exactly.

6. **Loop** back to step 1. Continue until:
   ```bash
   python3 locales/scripts/i18n tasks next <LOCALE> --stats
   ```
   shows **0 pending**.

## Translation rules

- **Preserve every interpolation/markup token verbatim and in count.** Keep the
  same set and the same number of: `{var}`, `{{var}}`, `%{var}`, `%s`, `<tag>`.
  Never translate, reorder away the meaning of, add, or drop a token.
- **Brand names stay English:** Onetime Secret, Identity Plus, Starlight.
- **Honor the resolved artifact:** apply `register` (form/pronoun, formality),
  use the bound `glossary` renderings, satisfy the binding rules, never emit a
  `forbidden_token`, and never reintroduce a declined decision.

## Audit stage (after a locale drains)

Because `--validate` does not gate writes, the queue showing 0 pending does not
prove the writes are clean. After a locale drains, audit its completed rows for:

- **key-set match** — each completed row's keys equal the source keys exactly.
- **token preservation** — every `{var}`, `{{var}}`, `%{var}`, `%s`, `<tag>`
  from the source survives in the translation, with the same set and count.
- **untranslated-English leakage** — values left in English where a translation
  was expected.

Fix any problem in place by rewriting `/tmp/trans_<LOCALE>.json` with the
corrected object and re-running:
```bash
python3 locales/scripts/i18n tasks update <ID> --file /tmp/trans_<LOCALE>.json --validate
```

## Out of scope for agents

Do **not** export (`tasks export`), do **not** sync (`pnpm run locales:sync` /
`content compile`), and do **not** commit or create branches. Those are human
steps documented in `TRANSLATION_PROTOCOL.md`. The agent's job ends when the
locale shows 0 pending and the audit is clean.
