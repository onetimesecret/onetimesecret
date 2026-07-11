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

> **Status (2026-07-10, shipped):** C4 landed across install.sh, the root
> README, the signup path, and the proof-of-life harness.
> **QS-3/BM-07:** both install.sh "Next steps" branches (full and simple)
> now print the account-creation commands (`bin/ots customers create EMAIL
> --role colonel` plus the `bin/ots apitoken` follow-on), and the root
> README gained a "Create your first account" section — `docker exec`,
> `docker compose exec app`, and bare-metal forms — linked from the Docker
> quick start, the bare-metal Installation block, and the Docker Compose
> section, with the self-hosting note on `AUTH_AUTOVERIFY` and signup's
> SMTP dependency. **QS-13:** the pending-login verification message
> composes with the customer's email instead of the objid (tryout guard
> added); the `set_info_message` channel that would show that string to
> users remains a removed stub — restoring it is out of scope here, the
> string is fixed at the source. **DX-6, the minimal cut:**
> `send_verification_email` now reports delivery success/failure and the
> signup path logs an operator-actionable warn on failure (fix emailer
> config, set `AUTH_AUTOVERIFY=true`, or `bin/ots customers verify EMAIL`);
> doctor surfacing stays with C9 as planned. **Proof:** proof-of-life grew
> an opt-in create-account + authenticated `/api/v2/account` step, gated on
> `POL_CREATE_ACCOUNT=1` (default off — existing lanes byte-identical);
> wiring it into the compose-smoke lane is follow-on CI work alongside
> C7's residuals. **Deferred:** `rake dev:seed` (D6) — the optional bullet,
> not built; and a comment pair above `.env.reference`'s bare
> `AUTH_AUTOVERIFY=false` explaining both polarities — that file is
> untouched, and C9 turns it into a generated/CI-checked artifact anyway.

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

> **Status (2026-07-10, shipped):** the rest of C5 landed. **CP-6:** the
> simple stack publishes Valkey on `127.0.0.1:6379` only, with the
> delete-the-port collision remedy and in-network `valkey-cli` debugging
> documented (docker/README "Debugging Valkey"); the full stack stays
> expose-only. (Scout preferred dropping the port entirely; the loopback
> bind with documented override was the deliberate call.) **CP-5:** the
> simple stack no longer mounts `./data` at all; the full stack's
> `/app/data` moved to the shared `onetime_app_data` named volume, with the
> bind-mount override + Linux chown step and `auth.db` migration documented
> — the compose-smoke workaround flagged in the note above is deleted.
> **CP-7/QS-4:** all four image refs default to `${OTS_IMAGE_TAG:-<pin>}`
> matching the root README's tag, with the lockstep-bump rule in
> docker/README "Image Version" (release checklist: bumping the README pin
> now also means bumping the compose defaults; the `docker-run-readme` CI
> job self-heals by grepping the README at runtime). **CP-3/CP-4:** the
> crash-looping `jobs worker`/`jobs scheduler` commands fixed to the real
> top-level subcommands, `JOBS_ENABLED` surfaced (default `false` →
> synchronous email, the full stack works without touching it; documented
> in `.env.example` alongside `OTS_IMAGE_TAG`), and
> docker/README gained the required-env table (`ARGON2_SECRET` listed as
> strongly recommended). **CP-10:** the app service's dead `PUBLIC_DIR`
> removed from the full stack. **CP-9:** stack switching documented as what
> it is (include-edit or direct `-f`), *not* migrated to real profiles —
> simple and full define app/maindb with colliding `container_name`s, so
> profiles would force a single-file merge breaking every documented
> invocation and the compose-smoke lint matrix. **CP-13:** the naming
> convention documented in docker/README (renaming rejected: 6+ reference
> sites for zero functional gain). **QS-5/QS-12/QS-7 entrypoint hygiene:**
> dead 2025-07 migration guard deleted; STDOUT_SYNC double-exec removed
> (the env var itself is still live in app code — only the broken shell
> gate died, don't scrub it from docs); healthcheck.sh parses
> `/health/advanced`'s top-level status via `ruby -rjson` (no new image
> deps), so degraded-but-serving now reports unhealthy — safe for the
> simple stack because `not_configured` sub-checks (e.g. RabbitMQ with jobs
> off) are excluded, but worth a CHANGELOG line, and it means the
> healthcheck requires `ruby` on PATH. All four documented compose combos
> pass `config -q`. **Still open, routed to owners rather than implied
> done:** the Dockerfile does not yet create `/app/data`, so the named
> volume needs the documented one-time chown on current published images;
> entrypoint.sh's vestigial `/mnt/public` copy block (CP-10's other half);
> headers cross-referencing `docker-compose.yml` ↔ `compose.test.yml`
> (CP-13's root-file half); and the full-stack `up --wait` lane (blocked on
> the Dockerfile fix reaching a published tag, plus the proxy service being
> build-only) — tracked with C7's residuals.

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
> (2) the macOS lane; (3) full-stack compose `up` — still only linted; C5
> cleared the original `JOBS_ENABLED`/required-env blocker, and the
> remaining blockers are the `/app/data` Dockerfile fix reaching a
> published tag plus the proxy service being build-only (see C5's status
> note); (4) `pnpm run build` + asset probe as a lane.

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

> **Position (2026-07-10):** C1–C5 done — C3 with the recorded direnv/
> overmind scope-down, clean-room validated (see
> [install-onboarding-clean-room-validation.md](./install-onboarding-clean-room-validation.md)),
> NF-1–NF-5 fixed, C7 shipped, and C4 and C5 landed (each with the
> deferrals and routed residuals listed in its status note). Next per this
> sequencing: **C6 → C8**, with C9 and C10 scheduled by appetite.
