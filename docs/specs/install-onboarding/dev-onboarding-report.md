# docs/specs/dx.md
---

# Why commits and pushes are slow — and where quality checks should live

**Repo:** onetimesecret · **Date:** 2026-07-11
**Inputs reviewed:** `.pre-commit-config.yaml`, `.pre-push-config.yaml`, installed `.git/hooks/*`, `package.json`, `eslint.config.ts`, `tsconfig.json`, `.github/workflows/ci.yml`

Scale that matters: **792 `.ts` + 320 `.vue` files in `src/`** (~1,100 files in the TS program), **1,014 `.rb` files**, **961 locale JSON files**.

---

## Part 1 — Root causes

### 1.1 Type-aware ESLint runs on every commit — twice

`eslint.config.ts` wires `parserOptions.project: './tsconfig.json'` into essentially every block (lines 169, 192, 330, 429, 552). That makes ESLint **type-aware**: before it can lint even a single staged file, it must build the full TypeScript program over all ~1,100 `src/` files. Staged-file filtering doesn't help — the program build cost is fixed and dominates.

And it happens **twice per commit**, because two hooks lint the same `\.(ts|vue|mjs)$` files:

1. **`eslint` (isolated env)** — pre-commit's own node environment with 17 pinned `additional_dependencies` (typescript, vue plugin, tailwindcss 4 + plugin, vue-i18n plugin, …). No `--cache`. Cold program build every time.
2. **`pnpm-lint`** — the project's ESLint via `pnpm exec`, with `--cache`. The cache helps per-file results but **not** the type-program build, which is redone each invocation.

So a one-line change to a single `.vue` file pays for two full ~1,100-file program constructions. This is almost certainly the bulk of your commit latency.

The isolated env has a second cost: it duplicates `package.json` versions by hand ("sync versions with package.json to avoid config drift", per its own comment), needs `pre-commit clean` after updates, and re-solves the same problem CI already solves (clean-environment consistency).

### 1.2 RuboCop boots a fresh process from a pre-commit-managed gem env

The `rubocop` hook uses the upstream `rubocop/rubocop` repo with 4 plugin gems installed into pre-commit's private environment. Every commit pays Ruby interpreter + RuboCop + 4 plugins boot (typically 3–8s) even for one staged file — and the pinned versions (`v1.81.7` + plugin pins) live outside `Gemfile.lock`, so the hook can disagree with `pnpm run rubocop` / CI, which use `bundle exec`.

### 1.3 Framework overhead × 3 stages per commit

Hooks are installed for `pre-commit`, `prepare-commit-msg`, and `post-commit` (plus `post-checkout`/`post-merge`). Each stage spawns Python + the pre-commit framework separately (~0.5–1.5s each), so every commit pays that startup tax three times before any hook logic runs. The `post-commit` stage exists solely to write `.commit_hash.txt`; `check-hooks-apply`/`check-useless-excludes`/`identity` meta hooks run every commit but only matter when the config itself changes.

### 1.4 Pre-push redoes the entire CI T1 job locally

`.pre-push-config.yaml` runs, on **every push**:

- `pnpm run lint` — full-project type-aware ESLint over all of `src/` (`always_run: true`, no filenames). Minutes, not seconds, at this repo size.
- `pnpm run type-check` — full `vue-tsc --noEmit` over the same ~1,100-file program (runs whenever any pushed commit touches a `.ts`/`.vue` file — i.e., nearly always). On a codebase with 320 SFCs this is commonly 1–3+ minutes.

Both are **exact duplicates of CI's `T1 · TypeScript Lint` job**, which runs `pnpm type-check && pnpm lint` on every PR with path filtering. The local pre-push run buys you feedback a few minutes earlier than CI at the cost of blocking every push — including pushes to WIP branches where you don't want that gate at all.

Minor: the pre-push config pins `pre-commit-hooks` at `v4.6.0` while pre-commit uses `v6.0.0` — two cached environments for the same repo, and version drift.

### 1.5 What's already right

Worth saying: the *architecture intent* is correct (light pre-commit, heavier pre-push, full CI), CI is genuinely good (path-filtered tiers, pinned actions, concurrency cancellation), `fail_fast: true` on commit is right, and the hygiene hooks (whitespace, merge-conflict, private-key, large-files, `no-commit-to-branch`, issue-prefix) are exactly what belongs in pre-commit. The problem is that two type-aware ESLint passes and a full type-check crept into the "light" layers.

---

## Part 2 — Measure before/after

Real numbers on your machine (estimates above are estimates):

```bash
# Per-hook timing for a typical commit's files
pre-commit run --verbose --files src/some/File.vue

# Pre-push timing
time pre-commit run --config .pre-push-config.yaml --all-files --verbose
```

---

## Part 3 — Recommended layering

The principle: **each layer catches what it's uniquely positioned to catch, at the latency budget of that layer.** Hooks are advisory (anyone can `--no-verify`); CI + branch protection is the enforcement point. So hooks should optimize for DX, and CI for rigor.

| Layer | Budget | Job |
|---|---|---|
| Editor (LSP) | instant | type errors, lint-as-you-type, format-on-save |
| pre-commit | < 5s | hygiene + syntax-level lint on staged files only |
| pre-push | < 30s, skippable | incremental type-check (optional) |
| CI (PR) | minutes | full type-aware lint, type-check, tests — **the gate** |
| Merge queue / protection | — | enforcement that CI passed |

### 3.1 Pre-commit: one ESLint pass, no type-program build

**Drop the isolated `eslint` hook entirely.** Keep one ESLint invocation via `pnpm exec`, using a **non-type-aware config** for the hook path. The cleanest way: add a lint script that disables type-aware parsing, e.g. an `eslint.config.hooks.ts` that reuses your config but sets `parserOptions.projectService: false` / `project: null` and drops the type-checked rule sets. Syntax + style + vue + import-order rules still run per staged file in ~1–3s; type-aware rules move to pre-push/CI where the program build is amortized.

```yaml
# .pre-commit-config.yaml — replace both eslint hooks with:
- repo: local
  hooks:
    - id: eslint-staged
      name: ESLint (syntax, staged files)
      entry: pnpm exec eslint --quiet --fix --cache
             --cache-location ./node_modules/.cache/eslint-hooks
             --config eslint.config.hooks.ts
      language: system
      files: \.(ts|vue|mjs)$
      exclude: ^src/tests/
```


**RuboCop: switch to the bundled gem in server mode.**

```yaml
- repo: local
  hooks:
    - id: rubocop
      name: RuboCop (server, staged files)
      entry: bundle exec rubocop --server --force-exclusion --autocorrect
      language: system
      types: [ruby]
```

`--server` keeps a daemon warm: first run pays boot, subsequent commits are sub-second. Versions come from `Gemfile.lock`, so the hook, `pnpm run rubocop`, and CI can never disagree again.

**Trim stages.** Remove `check-hooks-apply`/`check-useless-excludes`/`identity` from the per-commit path (run them in CI or via `pre-commit run` manually when editing the config). Consider whether `.commit_hash.txt` justifies a whole `post-commit`/`post-checkout`/`post-merge` framework spawn — a build step that calls `git rev-parse --short=7 HEAD` at build time does the same job with zero commit-time cost.

### 3.2 Pre-push: cheap incremental check or nothing

Delete `pnpm run lint` from pre-push — CI runs it on every PR and it's the layer that's actually enforced. For type-checking you have two reasonable stances:

- **Lean (recommended):** delete the pre-push config entirely. Push freely; CI gates the merge. This is what your path-filtered, tiered CI was built for.
- **Safety-net:** keep only an incremental type-check. You already have `"incremental": true` + `.tsbuildinfo`, so warm `vue-tsc --noEmit` runs only re-check what changed — typically 5–20s instead of minutes. Keep `fail_fast`, and document `git push --no-verify` / `SKIP=typescript-check-full git push` for WIP branches.

If you keep it, align the `pre-commit-hooks` rev with the commit config (`v6.0.0`) — the YAML/JSON/case-conflict checks there are cheap and fine.

### 3.3 CI: pick up what the hooks drop

CI already runs the expensive checks. Two additions close the gaps left by slimming hooks:

1. **Hygiene job** — hooks can be skipped, and the whitespace/EOF/private-key checks don't currently run in CI at all:

```yaml
hygiene:
  name: T1 · Hygiene (pre-commit)
  runs-on: ubuntu-24.04
  timeout-minutes: 3
  steps:
    - uses: actions/checkout@<pin>
    - uses: actions/setup-python@<pin>
    - run: pipx run pre-commit run --all-files --show-diff-on-failure
```

(~30–60s with pre-commit's env cache via `actions/cache` on `~/.cache/pre-commit`.) This also runs the meta hooks you removed from the commit path. Alternatively, [pre-commit.ci](https://pre-commit.ci) does this as an app and **auto-pushes fixes** (trailing whitespace, EOF, eslint --fix) to the PR branch — fixups stop costing local round-trips entirely.

2. **Enforcement** — make `T1 · TypeScript Lint`, `T1 · Ruby Lint`, and the hygiene job **required status checks** on `develop`/`main`, and consider GitHub's **merge queue** so the synthetic-merge testing you already document in ci.yml is guaranteed against the actual merge state. With that in place, local hooks are purely a convenience layer and skipping them is always safe.

### 3.4 Editor layer: make the feedback loop instant

The checks people most want *before* commit are the ones the editor can show live: ESLint extension (flat-config aware) + Volar for vue-tsc diagnostics + ruby-lsp with RuboCop formatting + format-on-save with Prettier. A committed `.vscode/extensions.json` (you have `.vscode/` but no `extensions.json`) and `settings.json` entries for `"editor.codeActionsOnSave": {"source.fixAll.eslint": "explicit"}` move most lint fixes to save-time, which is the cheapest place they can possibly happen. Zed users get the same via `.zed/settings.json` (you have `.zed/` already).

---

## Part 4 — Expected impact

| Path | Today (estimated) | After |
|---|---|---|
| `git commit` (1 file) | 2 × full TS program build + RuboCop cold boot + 3 framework spawns → ~1–3 min cold | hygiene + syntax lint + warm RuboCop server → **2–5s** |
| `git push` | full ESLint + full vue-tsc → ~2–5 min | nothing, or incremental vue-tsc → **0–20s** |
| Quality regression risk | hooks skippable, CI partially duplicative | **lower** — CI + required checks enforce everything hooks did, plus hygiene checks CI never ran before |

## Suggested order of operations

1. Measure baselines (Part 2) so you can prove the win.
2. Pre-commit: remove isolated `eslint` hook; add `eslint.config.hooks.ts` (non-type-aware) for the staged-files hook; switch RuboCop to `bundle exec rubocop --server`.
3. Pre-push: delete lint + full type-check (keep incremental vue-tsc only if you want the safety net); align hook revs.
4. CI: add the hygiene job (or enable pre-commit.ci); mark T1 jobs as required checks; evaluate merge queue for `develop`.
5. Editor: commit `.vscode/extensions.json` + fix-on-save settings.
6. Update `CONTRIBUTING.md` ("let them run" section) and `bin/setup` if hook install commands change.

Each step is independent and safe to land separately — 2 and 3 are where the minutes come back.
