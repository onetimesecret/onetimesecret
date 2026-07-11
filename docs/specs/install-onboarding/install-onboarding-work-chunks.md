---
title: Install Onboarding — Work Chunks
type: plan
status: draft
updated: 2026-07-11
---

# Install Onboarding: Work Chunks

The findings from the [current-state audit](./install-onboarding-current-state.md)
(QS/CP/BM/DX/TR/VER/DUP/GH series), the
[dev-onboarding recommendations](./dev-onboarding-problem-space.md) (D-series),
the [operator recommendations](./install-onboarding-problem-space.md)
(R-series), and the
[testing strategy](./install-onboarding-testing-strategy.md), packaged into
cohesive, independently-shippable chunks. Pick chunks, not findings.

Effort is calendar-honest solo-maintainer scale. "Proof" says how we know the
chunk worked — every chunk lands with its regression guard or names the chunk
that will guard it.

| # | Chunk | Effort | Depends on |
| --- | --- | --- | --- |
| C1 | Unbreak the front door (docs-only) | hours | — |
| C2 | Version truth | ~1 day | — |
| C3 | Bootable clean slate (script/code fixes) | 1–2 days | C2 helps |
| C4 | First account & first secret | ~1 day | — |
| C5 | Compose coherence | 1–2 days | C1 |
| C6 | `bin/setup` consolidation + CONTRIBUTING | 2–4 days | C2, C3 |
| C7 | Clean-room harness + CI lanes | 2–4 days | C3 (to go green) |
| C8 | Devcontainer + Codespaces | 1–2 days | C6 (or C3 min.) |
| C9 | Doctor v2 + drift guards + support bundle | 2–3 days | C2 |
| C10 | SECRET lifecycle safety | 2–4 days + design | — |

## C1 — Unbreak the front door (docs-only, zero code risk)

Every documented command works as pasted, on Linux, today.

- README compose quick start gains the SECRET one-liner (promote
  docker/README's recipe); or defers to docker/README as canonical.
- README `docker run` gains `--add-host=host.docker.internal:host-gateway`
  (promote the repo's own CI fix) — or switches to the user-defined-network
  form already written in the Dockerfile comments.
- Replace `cp --preserve --update=none` with a portable form (fails on macOS
  and Ubuntu 22.04 today).
- Pin the current release tag; restore the upgrade-callout pattern for v0.25.
- Bare-metal section: add `pnpm run build` before first boot; state the real
  Ruby/Node floors (pending C2 they're at least *consistent*); mention the
  UTF-8 locale requirement until C3 removes it.
- Kill trust papercuts: "Familia" paragraph, "three ways" (lists two),
  Dockerfile's `docs/docker.md` pointer, compose-under-Development placement.

Addresses: CP-1(doc), CP-2, CP-8, CP-14, QS-1(doc), QS-4, QS-10, QS-14(doc),
BM-01(doc), BM-11, DX-16. Proof: C7's scheduled lane later executes these
verbatim; until then, one manual clean-container paste-through.

## C2 — Version truth

One declaration per tool, read by everything (testing-strategy §6).

- Add `.ruby-version` (3.4.x) and `.node-version`; retire/symlink `.nvmrc`.
- Gemfile: `ruby file: ".ruby-version"` — retires the empirically-false
  `>= 3.3.6` floor.
- `check_version` compares floors sensibly (not exact-match); Node gate drops
  to what the build needs (22 LTS works — empirical runs 7/9); install-test's
  floor label corrected.
- CI: `ruby-version-file`/`node-version-file` everywhere (the pattern already
  exists at bump-api-docs.yml:86); fix EOL Node 20 workflow; 5-line grep
  asserting Dockerfile ARG matches pin files; align base.dockerfile's
  `pnpm@10` with `packageManager`.
- Document Python 3 as a build prerequisite wherever prerequisites are listed.

Addresses: VER-01…VER-10, BM-04, BM-08, QS-14, DX-9(F9), CI-oracle version
items. Proof: the CI grep + pin-file reads make regression structurally
impossible; empirical rerun of runs 1/5 flips to pass/clear-message.

## C3 — Bootable clean slate

A fresh machine that follows the (C1-fixed) docs reaches a working instance.

- **Locale crash**: read `.env` as UTF-8 explicitly in `OTSInit.read_env`
  (and audit other readers); either ASCII-fy `.env.example`/`config.ru`
  decorations or ensure every loader declares encoding. (Empirical run 8.)
- **Dev path boots**: install-dev.sh (or C6's bin/setup) runs
  `rake ots:secrets` when SECRET is empty; sets/documents
  `RACK_ENV=development`; Procfile.dev.example boots `etc/puma.rb` (the file
  installers set up), with the valkey line's story decided (in or documented
  out).
- **Gates → fallbacks**: direnv optional (generate .envrc, explain both
  flows, check the hook when present); bin/dev falls back without overmind;
  bin/backend/bin/frontend work overmind-free and inherit bin/dev's env
  protections (or Option B docs change to match reality).
- **install-test.sh** runs `schemas:json:generate` (TR-01); `.test-mode`
  gets a visible banner + documented exit (TR-02).
- **Ghost `.env.sh` purge**: bin/console, bin/worker, bin/scheduler,
  .env.example header, systemd units → `.env` with `set -a` (BM-03, DX-11,
  CP-12); systemd units also create/relocate their `ReadWritePaths` dirs
  (BM-02).
- Full-auth init ordering: preflight RabbitMQ/Redis *before* `queue init`,
  or defer queue init with a clear next-step (BM-06); Redis detection by
  connectivity, not local CLI presence (BM-05 — small; full doctor work is C9).

Addresses: run-8 locale bug, DX-1, DX-2, DX-4, DX-5, DX-10, DX-11, DX-12,
TR-01, TR-02, BM-02, BM-03, BM-05(min), BM-06, CP-12, DUP ghost-file +
procfile items. Proof: C7's fresh-clone job; until then, rerun the empirical
suite (runs 3, 4b, 5, 8, 10 all flip to green).

> **Status (2026-07-10, post-#3708 + NF fixes):** C3 landed with one
> deliberate scope deviation, recorded here so the plan matches reality
> (clean-room validation §3): **direnv and overmind remain hard
> prerequisites of the contributor path** — documented in the README —
> rather than "gates → fallbacks" as specced above. direnv is load-bearing
> for the standardized env-loading story (.envrc + .test-mode switching);
> bin/dev requires overmind (or hivemind), and README Option B's
> production-style boot (`pnpm run build` + puma) is the overmind-free
> alternative. D1.1's fallback work is deferred: if it returns, it is a new
> chunk, not a silent C3 reopen. The run-3/4b proof criterion above is
> amended accordingly (run 3 green *with direnv present*; run 4b resolved
> via Option B). Ruby-gate semantics (validation NF-5) were also decided:
> install.sh now enforces the **exact** `.ruby-version`, matching bundler's
> `ruby file:` pin, so the two gates cannot disagree. The clean-room
> validation's NF-1–NF-4 are fixed on `fix/onboarding-hell-contd1`.

## C4 — First account & first secret

Close the "instance up, now what?" gap on every path (the most-reported
issue shape after install itself: GH-4/GH-5 adjacency).

- Quick starts and install.sh "Next steps" print the admin/account commands
  (`bin/ots customers create EMAIL --role colonel`, `bin/ots apitoken EMAIL
  --create`) — promote from the commands' own usage comments and
  test-accounts.md.
- A self-host-facing note on `AUTH_AUTOVERIFY` and the SMTP dependency of
  signup; signup UX shows email not objid (QS-13); decide whether
  unverified-signup failure stays silent (DX-6 — minimally: log at warn and
  surface in doctor).
- Optional (ties to D6): `rake dev:seed` for contributors.

Addresses: QS-3, QS-13, BM-07, DX-6, D6. Proof: proof-of-life script
(testing-strategy §4) grows a create-account step; docs paste-through.

## C5 — Compose coherence

- App service gets a compose `healthcheck` (prereq for `--wait` everywhere);
  proxy/full-stack `depends_on` upgraded to `service_healthy` (CP-11).
- Stop publishing Valkey on 0.0.0.0:6379 by default (bind 127.0.0.1 or drop
  the port; document the debug override) (CP-6).
- Fix the Linux `./data` uid-1001 trap: named volume, or documented
  chown/init step (CP-5).
- Surface `OTS_IMAGE_TAG`; align default-tag story with README pinning
  (CP-7/QS-4); stack switching documented as what it is (include-edit), or
  moved to real profiles (CP-9).
- Full stack: required-env table in docker/README; `JOBS_ENABLED` story
  (what it needs, what crash-loops without it) (CP-3/CP-4); remove vestigial
  static-asset wiring (CP-10).
- Entrypoint hygiene: delete dead migration guard (QS-5), fix STDOUT_SYNC
  double-exec + debug-gate mismatch (QS-12); healthcheck.sh parses status
  properly instead of unanchored grep (QS-7).
- One root-level compose naming convention + cross-references (CP-13).

Addresses: CP-3…CP-11, CP-13, QS-5, QS-7, QS-12. Proof: C7's compose smoke
lane (`config -q` per combo + `up --wait` + proof-of-life).

> **Status (2026-07-11, partial):** the first bullet (CP-11) shipped early
> with C7's compose-smoke lane (PR #3712) because `up --wait` needs it: app
> `healthcheck` in both compose files, proxy `depends_on` upgraded to
> `service_healthy`, and the `OTS_IMAGE_TAG` doc comments bumped to v0.25.11
> in passing. Everything else in C5 is open. Two markers already waiting in
> the lane: `compose-smoke.yml` carries a CP-5 workaround (`chown 1001
> ./data` in the workflow) to delete when CP-5 is fixed properly, and the
> full stack is `config -q`-linted but never booted — C5's CP-3/CP-4 work is
> what unblocks a full-stack `up` lane.

## C6 — `bin/setup` consolidation + CONTRIBUTING (D2, D3, D7)

The one-command contributor path, built on install-test.sh's spine; the
three install scripts become thin delegates during a deprecation window;
CONTRIBUTING.md/SUPPORT.md/CoC; docs/development rewritten to one sequence;
package.json gains the `setup`/entry scripts story (DUP: 138-scripts item);
stale dev docs corrected or deleted (DX-13, DX-14, TR-07, TR-08, TR-11).

Addresses: D1–D3, D7, DX-3, DX-8, TR-06, DUP console/scripts items. Proof:
C7's fresh-clone job runs `bin/setup` itself — the Zulip property.

## C7 — Clean-room harness + CI lanes (testing-strategy §§2–4)

`scripts/test-install/` harness (pinned-image lanes, POSIX-locale lane,
idempotency re-run, `docker diff`, proof-of-life script) + the four CI lanes:
compose smoke (PR + scheduled-published-tags), installer matrix
(path-filtered, incl. one macOS runner + bash-3.2 gate), fresh-clone
contributor job (duration charted = TTFHW proxy), README-command drift grep.
This is R0.1 and R0.3 made concrete, and the permanent guard for C1–C6.

Proof: it *is* the proof mechanism; its own guard is that it runs on cron,
so registry/runner rot surfaces as a red scheduled run.

> **Status (2026-07-11, shipped):** C7 landed as three PRs on
> `integration/onboarding`: #3711 (2c — fresh-clone contributor lane +
> docs-command drift guard), #3712 (2a — compose-smoke lane + the CP-11 app
> healthcheck it needed; see C5's note), #3713 (2b — installer matrix +
> `scripts/test-install/run.sh` container harness). What exists:
> `scripts/test-install/{run.sh,proof-of-life.sh,check-docs-commands.sh}`
> and four workflows —
> - `installer.yml`: pinned-image lanes baremetal (`ruby:3.4.9-slim`),
>   posix-locale (empty `LANG`), ruby-old (`ruby:3.3-slim`, asserted-error),
>   each with an idempotency re-run; plus a bash-3.2 `bash -n` parse gate.
> - `compose-smoke.yml`: `config -q` on every documented combo, simple-stack
>   `up --wait` + proof-of-life on `docker/**` PRs; README `docker run`
>   verbatim against the README-pinned tag, cron-only.
> - `fresh-clone.yml`: `install-test.sh` from zero → `test:rspec:fast` with
>   no build (TR-01) → vitest → second `install-test.sh` (idempotency) →
>   litter check; duration reported in the step summary as the TTFHW proxy.
> - `docs-command-drift.yml`: runs `check-docs-commands.sh` on doc/entrypoint
>   PRs (no cron — it checks repo-internal consistency, nothing rots).
>
> The three heavy lanes run weekly crons (the registry/runner-rot guard);
> `check-version-pins.sh` runs in `validate-config.yml`. Deliberate
> deviations from the list above: **no macOS runner yet** — the bash-3.2
> parse gate stands in for testing-strategy §3.2b's `macos-15` lane, which
> is deferred (a parse gate catches bashisms, not BSD-tool behavior);
> **no container `docker diff`** litter check (fresh-clone's git-tree litter
> check covers the contributor-path analogue; it warns rather than fails on
> lockfile churn — frozen installs are C3/C6 work); duration is a per-run
> step summary, not charted/alarmed over time. **Still open, tracked here
> rather than implied done:** (1) a bare-metal boot lane — `rake ots:secrets`
> + puma + proof-of-life under `LANG=C` (the clean-room validation recipe's
> middle step; today no lane boots the app outside a container image, so the
> run-8 locale regression is guarded at secret-generation but not at boot);
> (2) the macOS lane; (3) full-stack compose `up` — only linted today,
> blocked on C5's `JOBS_ENABLED`/required-env work; (4) `pnpm run build` +
> asset probe as a lane.

## C8 — Devcontainer + Codespaces (D5, testing-strategy §5)

Compose-based devcontainer, `postCreateCommand: bin/setup`, `devcontainers/ci`
weekly workflow, GHCR prebuild cache. Gives contributors zero-install entry
and gives *you* the on-demand clean room. Proof: the weekly workflow.

## C9 — Doctor v2 + drift guards + support bundle (R0.2, D8)

Doctor = diff(manifest, reality): reads pin files, probes connectivity
(fixes BM-05 fully), separates operator vs dev contexts (BM-10), reconciles
the three health-checkers (DUP trio; QS-7 fixed in C5), adds
`--bundle` (sanitized diagnostic archive — R0.2). `.env.reference`
completeness check (QS-11, DS env-reference item) becomes a generated or
CI-checked artifact.

Proof: doctor's own checks run in C7's lanes; bundle format has a golden-file
test.

## C10 — SECRET lifecycle safety (QS-6)

Needs a short design first: boot-time key fingerprint (e.g., HKDF-derived
verifier stored in Valkey; warn loudly on mismatch), and make a mismatched
key *non-destructive* at reveal time (fail the claim before consuming, or
quarantine instead of burn). Separate risk class from everything above —
product code on the crypto path. Pairs with a documented rotation/backup
story.

Proof: unit specs for mismatch behavior + a harness lane that boots with a
rotated SECRET and asserts the secret survives a failed reveal.

## Not in any chunk (explicitly deferred)

- Runtime-config overlay, web wizard, first-admin web flow — the existing
  R1/R2 track in
  [install-onboarding-problem-space.md](./install-onboarding-problem-space.md);
  nothing above blocks it, and C4 shrinks the pain it addresses.
- Interactive `install.sh` prompts (R3.1) — after C6, and headless-first.
- Nix/devenv, docs-execution frameworks, `.gitpod.yml` — anti-recommended
  (testing-strategy §§6–7).

## Suggested sequencing

**Week 1:** C1 (day 1) → C2 → C3, then rerun the empirical suite — every
red run in the audit's §1 table should flip. **Week 2:** C7 to lock it in,
C4 and C5 in parallel (small, independent). **Then:** C6 → C8, with C9 and
C10 scheduled by appetite. C1+C2+C3 alone convert all three documented
paths from "fails on a clean machine" to "works"; C7 makes it stay that way.

> **Position (2026-07-11):** C1–C3 done (C3 with the recorded direnv/
> overmind scope-down), clean-room validated (see
> [install-onboarding-clean-room-validation.md](./install-onboarding-clean-room-validation.md)),
> NF-1–NF-5 fixed, C7 shipped (with the residuals listed in its status
> note), and C5's CP-11 bullet landed early. Next per this sequencing:
> **C4 and C5 in parallel**, then C6 → C8.
