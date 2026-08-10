# Agent Translation Protocol

> **Audience: a single automated background translator agent draining one
> locale.** This is the machine-executable spec the orchestration slash commands
> (`translate-parallel-agents`, `start-translation-session`,
> `translate-workflow` — vendored in `locales/slash_commands/`, installed under a
> command namespace such as `/i18n:`) point their `saas-translator` agents at. It is
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
branches, or **write** glossary decisions to the DB — those are human/orchestrator
steps in `TRANSLATION_PROTOCOL.md`. It **does** surface glossary _candidates_ in
its final report (see [Glossary candidates](#glossary-candidates-report-dont-write)),
which the orchestrator reviews and inserts after the drain.

Run everything from the repo root. The scripts need no environment setup (the
project uses direnv via `.envrc`; there is no `source .env.sh`).

## Precondition: resolved governance derived on demand

Per-locale governance is **derived on demand, not vendored** (no-vendor model;
translation-rules ADR-005). Before draining, the orchestrator runs
`locales/scripts/derive-governance.sh`, which derives every governed locale from
translation-rules at the canonical pin into the gitignored cache
`generated/i18n/.resolved/<LOCALE>.json`. Nothing is committed.

A locale is in the agent-drain set **only once**
`generated/i18n/.resolved/<LOCALE>.json` exists with a populated `register` and a
populated `glossary`. That file is the resolved governance artifact — the single
source of per-locale guidance for automated drain. If it is missing (the locale
is not governed upstream at the pin) or those fields are empty, the locale is
**out of scope** for automated drain until its governance is added in
translation-rules and the pin is bumped; skip it.

Agents read guidance from `generated/i18n/.resolved/<LOCALE>.json` and **only**
from there. Do **not** treat the derived human guides
(`generated/i18n/guides/for-translators/*.md`, curated upstream in
translation-rules) as the resolved artifact.

`generated/i18n/.resolved/<LOCALE>.json` carries:

- **`register`** — form/pronoun choice, formality, and `forbidden_tokens` the
  locale must never emit.
- **`glossary`** — agreed term senses with examples; the binding rendering for
  recurring domain/brand terms.
- **binding rules** — constraints that must hold for every translation.
- **declined decisions** — choices that were considered and rejected; do not
  reintroduce them.

### Register check (run locally)

Catch politeness-level violations (e.g. formal forms in an informal-locked
locale) before review — same engine as the `validate-register` CI gate. Needs
the resolved governance above.

```bash
# exit 0 = clean; 1 = lists each hit
python3 .translation-rules/lib/resolver/lint_content.py \
  --resolved generated/i18n/.resolved/<locale>.json \
  --content-root . \
  "locales/content/<locale>/*.json"
```

## Per-task cycle (one writer per locale, claim-free)

Loop this until the queue is dry:

1. **Get the next task** as JSON:

   ```bash
   python3 locales/scripts/i18n tasks next <LOCALE> --json
   ```

   Stop when there is no pending task. There is **one writer per locale**, so
   `tasks next` (which returns only _pending_ rows) advances with zero orphans —
   do **not** use `--claim`.

2. **Translate every value** in the task using the guidance from
   `generated/i18n/.resolved/<LOCALE>.json`.

3. **Write the result object** — a flat `{"key": "translation"}` map whose key
   set is the **EXACT source key set** (none added, none dropped) — to a
   per-locale temp file with the Write tool:

   ```
   /tmp/trans_<LOCALE>.json
   ```

   Per-locale paths keep concurrent agents from clobbering each other. Use a
   file, not inline JSON: apostrophes and quotes (common in fr/es/it) break
   shell single-quoting and HEREDOCs.

4. **Save it back** with the write gate:

   ```bash
   python3 locales/scripts/i18n tasks update <ID> --file /tmp/trans_<LOCALE>.json --validate --strict
   ```

5. **Check the exit status.** `--strict` makes the key-set check a **gate**: on
   any missing or extra key the command prints the mismatch, writes **nothing**
   to the DB, and exits 1. A non-zero exit means the task is still pending —
   rebuild `/tmp/trans_<LOCALE>.json` with the exact source key set and re-run
   step 4 until it exits 0. Do not move on to the next task on a failed write.
   (Bare `--validate` without `--strict` only warns and saves anyway; always
   pass both.)

6. **Loop** back to step 1. Continue until:
   ```bash
   python3 locales/scripts/i18n tasks next <LOCALE> --stats
   ```
   shows `pending: 0`. That ends the loop, not the job — go to
   [Audit stage](#audit-stage-after-a-locale-drains).

## Translation rules

- **Preserve every interpolation/markup token verbatim and in count.** Keep the
  same set and the same number of: `{var}`, `{{var}}`, `%{var}`, `%s`, `<tag>`.
  Never translate, reorder away the meaning of, add, or drop a token.
- **Brand names stay English:** Onetime Secret, Identity Plus, Starlight.
- **Honor the resolved artifact:** apply `register` (form/pronoun, formality),
  use the bound `glossary` renderings, satisfy the binding rules, never emit a
  `forbidden_token`, and never reintroduce a declined decision.

## Audit stage (after a locale drains)

An empty queue is not a clean locale: `pending: 0` says every row left the
queue, not that what it wrote is correct. **A drained locale is done only when
the audit exits 0.** Run it on the completed rows in the DB, before any export:

```bash
python3 locales/scripts/i18n tasks audit <LOCALE> --strict
```

`--strict` exits 1 on any **error** finding, and also when zero completed rows
could be checked — a gate that verified nothing must not read green. Without
`--strict` the audit is advisory and exits 0. Each finding names the task ID,
key, severity, and which check failed:

- **status** (error) — no row left in `in_progress`. A claimed-then-abandoned
  row is counted separately from `pending`, so it makes the locale _look_
  drained while its keys never export. Release it with
  `tasks update <ID> --status pending` and translate it.
- **key-set match** (error) — each completed row's keys equal the source keys
  exactly, and none of the values is blank. A whitespace "translation" passes a
  naive key comparison but `tasks export` skips it, so the key would stay
  English forever.
- **token preservation** (error) — every `{var}`, `{{var}}`, `%{var}`, `%s`,
  `<tag>` from the source survives in the translation, with the same set and
  count. Compared **per plural form**: the number of `|`-separated forms is a
  property of your language (en 2, ja 1, ru 3) and is never itself a finding.
- **untranslated-English leakage** (**advisory** — reported, never gates) —
  values left byte-identical to the English source. Treat it as a review list,
  not a task list: an identical string is the _correct_ answer for many short
  labels ("Status", "TTL", "Redis", "Amazon SES", "Canada"). Never invent a
  wrong translation to silence it. Brand names that must stay English (Onetime
  Secret, Identity Plus, Starlight), empty sources, `skip` keys, and strings
  with no letters (numbers, punctuation, bare placeholders) are already
  excluded.

Fix each **error** finding in place: rewrite `/tmp/trans_<LOCALE>.json` with the
corrected object for that task ID and re-run

```bash
python3 locales/scripts/i18n tasks update <ID> --file /tmp/trans_<LOCALE>.json --validate --strict
```

then re-run the audit. Loop until it exits 0. `export-all.sh` runs the same
`--strict` audit as its export gate, so a locale you leave with error findings
is not exported at all. Advisory findings do not block the export; report the
ones you believe are genuine leaks alongside your glossary candidates.

## Glossary candidates (report, don't write)

Do **not** `INSERT INTO glossary`. The task DB is one file shared by every
parallel locale agent, and the shared committable tables are the
orchestrator's to write — concurrent agent writes are the boundary this
protocol exists to hold.

Instead, while translating, note the renderings you settled on for recurring
domain/brand terms (secret, passphrase, burn, reveal, email, …) — especially
any that are **not** already fixed by the bound `glossary` in
`generated/i18n/.resolved/<LOCALE>.json`. Report them in your **final message**
as a short list, one per line:

```
GLOSSARY CANDIDATES (<LOCALE>):
- <en term> → <chosen rendering> — <one-line reason / sense>
```

The orchestrator reviews these and inserts the accepted ones after the drain.
This is the drain-time counterpart to the QC path
(`TRANSLATION_PROTOCOL.md` → "Glossary Updates from QC"); between the two,
agent-drained locales still accrue glossary entries. Emit the header even with
no candidates (`GLOSSARY CANDIDATES (<LOCALE>): none`) so the orchestrator knows
you considered it.

## Out of scope for agents

Do **not** export (`tasks export`), do **not** sync (`pnpm run locales:sync` /
`content compile`), do **not** commit or create branches, and do **not** write
the glossary/committable DB tables. Those are human/orchestrator steps
documented in `TRANSLATION_PROTOCOL.md`. The agent's job ends when the locale
shows `pending: 0`, `tasks audit <LOCALE> --strict` exits 0, and the glossary
candidates are reported.
