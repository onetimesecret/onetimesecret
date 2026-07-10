---
title: Install Onboarding — Current-State Audit
type: assessment
status: current
updated: 2026-07-09
---

# Install Onboarding: Current-State Audit

Ground-truth audit of every onboarding surface as of 2026-07-09 (main @
1c3e2ccb). Where
[install-onboarding-problem-space.md](./install-onboarding-problem-space.md)
describes the problem space strategically, this doc enumerates the specific
broken bolts, with evidence. It exists so the fix work
([install-onboarding-work-chunks.md](./install-onboarding-work-chunks.md)) can
be scoped against facts rather than impressions.

**Method.** Ten parallel audit passes (one per surface/concern), each finding
then adversarially verified by an independent pass that attempted to refute it
against the code; plus **empirical first-run transcripts** captured in a fresh
Linux container (Ruby 3.3.6/3.4.9 via rbenv, Node 22, pnpm 11.10.0,
redis-server, no direnv/overmind/pre-commit, POSIX locale — a realistic
"fresh contributor" profile); plus a GitHub issues sweep. Zero findings were
refuted; 35 had details corrected during verification (corrections are
incorporated below).

**Verification tags.** `[C]` confirmed by adversarial verification ·
`[P]` confirmed with corrections (as written here) · `[U]` unverified
(verification pass unavailable; treat as high-probability, spot-check before
load-bearing use) · `[E]` additionally confirmed by empirical execution.

**The headline.** All three documented entry points fail on a clean machine
before first success — while the machinery underneath is demonstrably sound
(§2). Nearly every common-path failure already has a correct implementation
elsewhere in the same repository: the compose SECRET fix is in
`docker/README.md`, the Linux networking fix is in the repo's own CI action,
admin creation is in a YAML comment, the right Node-pinning pattern is in
`bump-api-docs.yml`. The work is mostly **promotion and reconciliation of
existing correct answers into the paths people actually follow**, not new
construction. (Issue #2628 shows this is already understood — this audit
supplies the specific bolt list.)

---

## 1. Empirical first-run transcripts

Every run in a clean-room clone; full logs were captured during the audit
session. TTFHW context: once past the gates, the machinery is *fast* —
the product is minutes from a 15-minute clone-to-working-instance experience.

| # | Path exercised | Result |
| --- | --- | --- |
| 1 | `./install.sh init` (Node 22) | **DIES**: `Node too old: have 22, need 25+` — after warning `.ruby-version` missing (`version not verified`) |
| 2 | `./install.sh doctor` | Works; correctly enumerates gaps |
| 3 | `./install-dev.sh` | **DIES**: `Required tools missing: direnv` |
| 4 | README compose quick start | **DIES**: `required variable SECRET is missing a value ... run ./install.sh` — before any container starts |
| 4b | `bin/dev`, `bin/backend` | **DIE**: overmind required (including "Option B" `bin/backend`) |
| 5 | `./install-test.sh` on Ruby 3.3.6 (Gemfile-legal) | **DIES**: kanayago native-extension build failure — the Gemfile floor `>= 3.3.6` is factually wrong |
| 7 | `./install-test.sh` on Ruby 3.4.9 | ✅ **EXIT=0 in 76s** — configs seeded, deps installed, test datastore up, config smoke-verified |
| 8 | `rake ots:secrets` + puma boot, POSIX locale | **DIES**: `Encoding::CompatibilityError` — UTF-8 box-drawing chars in `.env.example` comments crash `read_env`; UTF-8 in `config.ru` crashes `Rack::Builder.load_file`. Fresh servers/containers/systemd default to POSIX locale; maintainer desktops never do |
| 8b | Same, `LANG=C.UTF-8` | ✅ Boots; `GET /` 200; `/api/v2/status` `nominal` — but the page references **zero JS/CSS**; server log says `Run pnpm run build` (browser user sees nothing) |
| 9 | `pnpm run build` on Node 22 | ✅ **21s**; UI fully working (`/dist/assets/main.*.js` → 200) — the Node 25 gate blocks a version that demonstrably works |
| 10 | `pnpm run test:rspec:fast` | ✅ 260 examples, 0 failures, 2.6s — **but see caveat** |

**Run-10 caveat (a poisoned-well lesson in miniature):** RSpec passed only
because run 9's `pnpm run build` had already executed `schemas:json:generate`
as its prebuild. On a truly clean fork, `install-test.sh` never generates the
JSON schemas and its headline command fails (TR-01 below, `[C]`). Our own
clean room got contaminated by experiment ordering — exactly how maintainer
machines hide these bugs.

Environment boundaries, stated honestly: the compose *runtime* could not be
tested here (egress proxy 403s Docker Hub blobs); the compose finding (§3.2)
is the client-side interpolation failure, which occurs before Docker is
contacted. Docker-run networking (QS-1) is verified by code/CI reading, not
execution.

---

## 2. What demonstrably works (don't break it while fixing)

- **Secrets lifecycle**: one root SECRET, HKDF-derived children with versioned
  salt history, idempotent `rake ots:secrets` preserving independent secrets,
  `chmod 600`, runtime derivation of missing `IDENTIFIER_SECRET` using the
  same HKDF purpose (anti-drift by construction).
- **Boot guardrails**: missing/CHANGEME SECRET fails fast with actionable
  message; Redis URLs get accidental-quote stripping; connection failures log
  the offending URI.
- **The core product loop**: anonymous create → share → at-most-once reveal
  works out of the box with zero SMTP, and the reveal invariant is enforced by
  construction (decryption only inside the won atomic claim).
- **`install-test.sh`** is the closest thing to a true `bin/setup`: honest
  header promise, fail-fast tool checks with URLs, Valkey→Redis fallback,
  CI-mirroring config seeding, throwaway 2121 datastore, config smoke test —
  and it empirically delivers in 76s (modulo TR-01).
- **Test isolation** is layered and real: hermetic lane env-clearing, flushdb
  refuses any port but 2121, sqlite-only spec.rake, the 21xx port scheme.
- **Supply-chain pinning** of service images is excellent (digest-pinned
  Valkey/PG/RabbitMQ in CI and compose) — the *tool* versions are the mess,
  not the images.
- **`docker/README.md` is accurate end-to-end** — the one compose recipe in
  the repo that works. All docs.onetimesecret.com links in first-touch files
  resolve (200). README's HMR snippet matches live config keys.
- **CI ergonomics**: failed-test tails posted as PR comments; path filtering;
  digest pins.
- **`bin/dev`** already found and fixed the nastiest overmind footgun
  (`OVERMIND_SKIP_ENV=1` with a thorough explanation).
- **Issue hygiene**: fast fixes with releases (multiple 11-day
  report-to-release turnarounds), candid maintainer communication, proactive
  self-filed DX issues, consistent labeling.

## 3. Findings by surface

Severity: **B**locker (documented path fails/dead-ends) · **M**ajor ·
minor/papercut (tabled). IDs are stable for cross-referencing; compose and
contributor findings are prefixed CP-/DX- here to avoid ID collisions.

### 3.1 Docker `docker run` quick start (README §Quick Start)

- **QS-1 [B][C] The quick start fails on Linux — the majority self-host
  platform.** `host.docker.internal` (README.md:33) doesn't resolve on a stock
  Linux Docker engine; boot pings Redis and puma exits; no restart policy, so
  the container stays dead. `docker run` itself prints a container ID, so the
  failure is silent until the user checks `docker ps`/`logs`. **The repo's own
  CI passes `--add-host=host.docker.internal:host-gateway` on every run**
  (.github/actions/test-docker-container/action.yml:131) — the fix exists
  in-tree, unpromoted. It works on Docker Desktop (macOS/Windows), which is
  presumably how it got documented.
- **QS-3 [M][P] No path to a usable account.** Signup shows "verification
  email sent"; SMTP defaults to a placeholder host; the send fails and is
  rescued into an info message; sign-in stays "pending" forever (and displays
  an internal `cust_…` objid instead of the email — QS-13). The Quick Start
  never mentions SMTP, `AUTH_AUTOVERIFY`, `bin/ots`, or admin/colonel
  creation. The one-command fix (`docker exec CTR bin/ots customers create
  me@example.com --role colonel`) is documented only in the command's own
  `--help` usage comment (lib/onetime/cli/customers/create_command.rb:8-9);
  promoting an *existing* customer to colonel is documented separately
  (etc/defaults/config.defaults.yaml:269-272, `bin/ots customers role
  promote`). Neither is linked from any setup doc.
- **QS-4 [M][P] Version pinning incoherent across surfaces.** README pins
  v0.24.6 (~3.5 months old; one minor + one patch behind v0.25.11); the docs
  site pins differently; compose defaults to `:latest`. No v0.25 upgrade
  guide despite the README's upgrade-callout pattern for v0.23/v0.24.
- **QS-5 [M][C] Entrypoint's migration guard is dead code** — checks a path
  that has never existed in the tree; its printed remedy references a
  nonexistent script (docker/entrypoints/entrypoint.sh:84).
- **QS-6 [M][C] Lost/changed SECRET is undetected at boot and destructive at
  reveal**: the reveal claim persists *before* decryption, so each attempt on
  a pre-rotation secret errors AND permanently consumes it; restoring the
  right SECRET can't un-burn. Nothing fingerprints the key against stored
  data.
- **QS-7 [minor][P] The container healthcheck structurally can't fail while
  puma answers**: healthcheck.sh:49 greps the *whole* `/health/advanced` body
  for the unanchored substring `"status":"ok"` — any single healthy sub-check
  matches even when top-level status is `degraded`; plus a fallback to the
  unconditional-ok `/health`.

Minor/papercut: QS-8 [P] build-from-source fails as documented (bake version
guard + wrong flag syntax in its error); QS-9 [P] step-1 Redis is
unauthenticated on 0.0.0.0 with no persistence; QS-10 [C] Dockerfile:8 points
at nonexistent `docs/docker.md`; QS-11 [C] `.env.reference` claims
completeness but omits `AUTH_REQUIRED` — a var the README itself uses; QS-12
[C] entrypoint's STDOUT_SYNC debug branch runs the container command twice
(and its two debug gates disagree `true` vs `1`); QS-13 [P] verification
message shows objid not email; QS-14 [C] prerequisites contradict themselves
(see §4).

### 3.2 Docker Compose (README §Docker Compose)

- **CP-1 [B][C][E] The documented quick start dead-ends on empty SECRET** —
  `cp .env.example .env` leaves `SECRET=` empty; `${SECRET:?}` treats empty as
  unset; `docker compose up` aborts before any container starts. The error's
  advice ("run ./install.sh") routes a Docker persona into the bare-metal
  Ruby/Node toolchain — which itself dies on Node 22 (run 1). Empirically
  reproduced verbatim. `docker/README.md:26-28` contains the correct one-liner
  the root README omits (CP-2 [M][C]: three quick starts, mutually
  contradictory).
- **CP-3 [M][P] Full stack ships RabbitMQ + worker + scheduler that do
  nothing by default** (`jobs.enabled` defaults false), and nothing —
  `.env.example`, the compose env block, docker/README — mentions
  `JOBS_ENABLED` or what enabling it requires.
- **CP-4 [M][P] Full stack's real env requirements are undocumented** —
  guidance is literally "see the compose file for required secrets."
- **CP-5 [M][C] Linux bind-mount permission trap**: `./data` is created
  root-owned by the daemon while the container runs uid 1001 — full mode's
  SQLite auth DB (`sqlite://data/auth.db`) cannot be created.
- **CP-6 [M][C] Simple stack publishes the unauthenticated Valkey store on
  host 0.0.0.0:6379** — colliding with the README's own step-1 Redis, and
  exposing production data on LAN/cloud hosts.
- minor: CP-7 [C] compose defaults `:latest` vs README's pinned tag;
  `OTS_IMAGE_TAG` discoverable only in comments. CP-8 [C][E-adjacent]
  **`cp --preserve --update=none` fails on macOS and Ubuntu 22.04**
  (needs GNU coreutils ≥ 9.3) — the very first command of the quick start.
  CP-9 [C] switching stacks = editing a tracked file; README calls it
  "profiles" (a different Compose feature). CP-10 [P] vestigial static-asset
  wiring in full stack (Caddy *does* serve baked assets; the `/mnt/public`
  copy and empty-volume pieces are dead). CP-11 [P] proxy gates on
  `service_started` despite the image shipping a HEALTHCHECK. CP-12 [C]
  `.env.example` header's step 2 says `source .env.sh` (ghost file, §5).
  CP-13 [C] two root-level compose entry points with different naming and no
  cross-references (`docker-compose.yml` vs `compose.test.yml`). CP-14 [C]
  README files the production-shaped compose stack under "Development".

### 3.3 Bare-metal (README §Installation + install.sh)

- **BM-01 [B][P][E] The path ends at a blank UI**: neither the README
  Installation section nor install.sh's printed "Next steps" ever runs or
  mentions `pnpm run build` (it appears once, in the *Development* section as
  "Option B"). Empirically: boot succeeds, API nominal, page ships zero
  assets, and the only mention of the fix is a server-side log line.
- **BM-02 [B][P] The recommended systemd path fails twice over**: units set
  `ProtectSystem=strict` with `ReadWritePaths` naming directories that don't
  exist in a fresh clone (git ignores `log/` and `tmp/`; nothing creates
  them) so the mount-namespace setup fails; and `ExecStart` sources the ghost
  `.env.sh`. `Restart=on-failure` turns it into a restart loop.
- **BM-04 [M][C][E] Hard gate on Node ≥ 25 (non-LTS)** kills init for
  LTS/distro users, though Node is build-time-only and the build empirically
  works on 22 (runs 1, 9). CI itself builds on 22.
- **BM-05 [M][C] "Redis availability" is detected via local CLI binaries,
  not connectivity** — remote/containerized Redis reads as down forever.
- **BM-06 [M][P] Full-auth init is order-broken**: `bin/ots queue init
  --force` runs under `set -e` *before* the Redis check and *before* printing
  "Next steps: 1. Start Valkey/Redis and RabbitMQ" — so init aborts unless
  the services it later tells you to start are already up.
- **BM-07 [M][C] Nothing tells the operator how to create the first
  account/admin** (same gap as QS-3, bare-metal flavor).
- **BM-03 [M][C] Three contradictory env-loading stories**: `set -a; source
  .env` (install.sh/README) vs `source .env.sh` (systemd, .env.example,
  bin/console, bin/worker, bin/scheduler) vs `.envrc`/direnv (dev tooling).
- **[B][E] POSIX-locale crash (empirical run 8)**: UTF-8 decorative
  characters in `.env.example` comments and in `config.ru` crash
  `rake ots:secrets` (init.rake:21-22 `read_env`) and puma boot
  (`Rack::Builder.load_file`) with `Encoding::CompatibilityError` on any
  machine without a UTF-8 locale — fresh Debian/Ubuntu servers, containers,
  systemd units. Not surfaced by any static auditor; found only by execution.
- minor: BM-08 [C] `.ruby-version` gate is a no-op (file absent; and
  `check_version` is exact-match, so the moment the file exists it will
  reject every newer patch — VER-06). BM-09 [P] example puma binds 0.0.0.0
  with no reverse-proxy guidance. BM-10 [C] init always ends by running
  doctor, which mixes dev-tool warnings (overmind!) into a production
  operator's output. BM-11 [C] README papercuts ("This version of Familia…";
  "three ways" listing two).

### 3.4 Contributor dev path (README §Development + install-dev.sh + bin/*)

- **DX-1 [B][C][E] The recommended path can't boot the app**: install-dev.sh
  on a fresh clone (no `~/.config/onetimesecret-dev`) skips all config
  symlinks, copies `.env.example` → `.env` with **SECRET left empty**, never
  runs `rake ots:secrets`, and prints "Setup complete… To start: bin/dev".
  Empirically it dies even earlier — direnv is a hard requirement (run 3).
- **DX-2 [B][C] Even running BOTH scripts (install.sh init + install-dev.sh)
  yields no frontend**: nothing sets `RACK_ENV=development`; puma defaults to
  production; `ViteProxy` is only mounted in development
  (apps/web/core/application.rb:45-48); production `StaticFiles` serves the
  very `public/web/dist` that install-dev.sh just deleted (`pnpm run clean`);
  pages render a `console.warn` stub.
- **DX-4 [M][C] direnv hard-required, never documented**; the shell *hook* is
  never checked (installed-but-unhooked direnv passes the tool check and then
  nothing loads); bin/dev's failure message gives a wrong fix.
- **DX-5 [M][C] Documented "Option B: separate terminals" cannot work**: two
  overmind instances collide on one socket; `bin/backend`/`bin/frontend` also
  lack every protection `bin/dev` added (`OVERMIND_SKIP_ENV=1`, env guard).
- **DX-6 [M][P] First-login dead end, silently**: default `autoverify:
  false` + blank SMTP means web signup strands the first user with no error
  anywhere (the send failure is rescued); the CLI escape hatch
  (`bin/ots apitoken user@example.com --create`, documented well in
  docs/development/test-accounts.md) is never linked from any setup doc.
- **DX-10 [M][C] Option A never says to start Valkey/Redis**; Procfile.dev's
  valkey line is commented out; the carefully-copied `etc/puma.rb` is then
  ignored — Procfile.dev.example boots `etc/examples/puma.example.rb`
  (DUP: procfile-dev-wrong-puma-config).
- **DX-3 [M][P] / DX-8 [M][C] Entry-point documentation contradicts itself**
  (README says install-dev.sh alone; docs/development says install.sh init;
  neither says both) and **contributor scaffolding is absent**: no
  CONTRIBUTING.md, CODE_OF_CONDUCT.md, SUPPORT.md, devcontainer,
  `.tool-versions`; no good-first-issue signposting.
- minor: DX-11 [C] ghost `.env.sh` sourced by four bin/ scripts + systemd +
  .env.example. DX-12 [C] `bin/dev --volatile` advertised in three places;
  `Procfile.volatile` exists only in the maintainer's private config — no
  example, no fallback. DX-13 [P] dev-guide HMR snippet uses symbol-keyed
  YAML the string-keyed loader silently ignores (root README's snippet is
  correct — the two disagree). DX-14 [C] isolated-environments.md documents a
  `path/2/run/` DevBox/Flox tree that doesn't exist. DX-15 [P] bash-4
  hard-fail on stock macOS exists for a single associative array. DX-16 [C]
  trust papercuts (Familia paragraph; production-oriented values in
  .env.example).

### 3.5 Test lane (install-test.sh + CI parity)

- **TR-01 [B][C][E-corroborated] `install-test.sh`'s headline promise fails
  on a clean fork**: it never runs `schemas:json:generate`, and
  `test:rspec:fast` asserts on the generated schemas. CI and the unit lane
  both know the prerequisite; install-test.sh is the one consumer that
  forgot. (Our run 10 passed only via run 9's build side effect — §1.)
- **TR-02 [M][P] The `.test-mode` lane switch is invisible with an expensive
  exit**: gitignored marker + gitignored `.envrc`; every future shell in the
  checkout silently runs `RACK_ENV=test` (`.env.test` even sets it
  explicitly); the only documented way back is knowing to run
  install-dev.sh.
- **TR-03/TR-04 [M][P] Two parallel unlinked local test-service systems**
  (install-test.sh vs compose.test.yml + tests/lanes), and CI sets up
  ruby-unit differently from install-test.sh on five axes (built assets,
  schemas, random secrets, RabbitMQ service, try:unit ordering) — no single
  local command reproduces what CI runs. (TR-05's "21xx contradiction" was
  softened on verification: lanes docs explicitly declare partial adoption.)
- **TR-06 [M][C] Running tests is undocumented everywhere a newcomer reads**:
  no CONTRIBUTING.md, zero test content in the Development Guide.
- minor: TR-07 [C] broken script refs (`test:tryouts:clean` → nonexistent
  `pnpm valkey:clean`; dev guide documents nonexistent `database:*` scripts).
  TR-09 [C] Valkey→Redis fallback lives only in install-test.sh's process
  env, so `test:database:*` scripts fail later on Redis-only machines.
  TR-10 [C] CI path filter classifies `tests/**` as TypeScript. TR-11 [P]
  stale spec_helper comments; broken link in lanes README.

### 3.6 Version truth matrix (VER-01…13)

| Tool | Source of claim | Value |
| --- | --- | --- |
| Ruby | README.md:72 | "3.4+" |
| Ruby | Gemfile:13 | `>= 3.3.6` — **empirically false** (kanayago needs 3.4+; run 5) |
| Ruby | install-test.sh:76 | 3.4.7, mislabeled "the Gemfile floor" |
| Ruby | ci.yml:193, validate-config.yml:41 | hard-pinned **3.4.9** (lint) |
| Ruby | setup-ruby-test-env default | floating "3.4" (all test/integration/migration jobs) |
| Ruby | `.ruby-version` | **absent** — referenced by install.sh:179 and ci.yml:108 |
| Node | `.nvmrc` | **25** (non-LTS); install.sh gates `>= 25` and dies |
| Node | CI workflows | 22 (ci.yml ×3), 25 (e2e), **20 — EOL** (translation workflow) |
| Node | bump-api-docs.yml:86 | `node-version-file: .nvmrc` — **the one correct pattern in-tree** |
| Node | empirical | build + full UI works on 22 (runs 7, 9) |
| pnpm | package.json:6 | `packageManager: pnpm@11.10.0` (honored by CI setup actions) |
| pnpm | docker/base.dockerfile:88 | installs `pnpm@10` — self-corrects via packageManager at run time, silently |
| Bundler | Gemfile.lock | BUNDLED WITH 4.0.9; unpinned everywhere else |
| Valkey | CI + compose | digest-pinned 8.1.x ✓; README step 1: unpinned `redis:bookworm` |
| PostgreSQL / RabbitMQ | CI digests only | 17 / 4.x — no doc states supported versions |
| Bash | install-dev.sh | 4+ (for one associative array); others POSIX-safe |
| Python 3 | *(nowhere)* | [U] hard dependency of `pnpm run build`/locales; absent from every requirements list |

VER-06 [C]: `check_version` requires exact equality — creating
`.ruby-version` will start rejecting every newer patch release until the
comparison is fixed. VER-12 [P]: CI caching is disabled with "DEBUG" comments
left in. VER-13 [C]: `.npmrc` comment contradicts its own setting.

### 3.7 Duplication & drift map (DUP-*)

- **Config seeding: six implementations, three behaviors** [C] — install.sh
  (hardcoded 3-name list), install-test.sh (glob of all defaults — the only
  one that picks up new files automatically), install-dev.sh (symlinks),
  Dockerfile, CI action, entrypoint. A new `etc/defaults/*.defaults.yaml`
  file silently doesn't reach install.sh users.
- **`.env` parsed by four parsers with divergent semantics** [C] — install.sh
  sed (first match wins), Ruby `read_env` (last match wins), shell `source`,
  compose interpolation. The same file can yield different SECRETs to
  different consumers.
- **Ghost `.env.sh`** [C] — referenced by systemd units, `.env.example`,
  bin/console, bin/worker, bin/scheduler; created by nothing.
- **Secret generation in four flavors** [P] — `SecureRandom.hex(64)` (rake),
  `openssl rand -hex 32` (README ×2, docker/README, CI action), fixed dummies
  (tests). Both lengths work (HKDF normalizes), but the docs teach a weaker
  value than the tool generates, and nothing says which is canonical.
- **Three overlapping health checkers** [C] — install.sh doctor, docker
  healthcheck.sh, `bin/ots status` — different checks, different endpoints,
  plus QS-7's grep bug.
- **Four console entry points, three boot semantics** [U] — bin/console
  (sources ghost .env.sh), `bin/ots console`, `install.sh console`, bin/irb.
- **138 package.json scripts, no `setup`, and `dev` (frontend-only) collides
  with `bin/dev`** [U]; exact-duplicate script pairs.
- **`.envrc` heredoc duplicated** in install-dev.sh/install-test.sh [P] —
  currently byte-identical except the "generated by" line (the drift risk is
  structural, not yet realized).
- bin/backend & bin/frontend lack every protection bin/dev added [U];
  entrypoint STDOUT_SYNC double-exec [U] (= QS-12 [C]).

### 3.8 What users actually hit (GitHub issues sweep — all [U], issue-cited)

- **GH-1** #2628 (OPEN, maintainer-confirmed): bare-metal instructions
  contradictory across three sources — "it pains me to confront how awful the
  onboarding DX is right now" (maintainer), with a public gap analysis.
- **GH-2** recurring: releases break running docker/compose installs; users
  learn to pin around `:latest` (#1259 et al.).
- **GH-3** #3424: v0.25.x stable made every secret link show "no longer
  available" — the core loop dead on fresh installs; first report initially
  closed as stale.
- **GH-4** #1392: `COLONEL` env silently failed to grant admin across two
  releases; `/colonel` thin on fresh installs.
- **GH-5** #760 (OPEN since 2024): unauthenticated SMTP relay unsupported;
  failures silent or crash requests; defaults ship a fake host.
- **GH-6** #2702: env vars ignored for authenticated users; opaque formats;
  SaaS-tuned defaults.
- **GH-7** #1120: dev-oriented compose/entrypoint artifacts trap self-hosters
  (volume mount erasing built frontend — the container cousin of DX-2).
- **GH-8** #1768 (OPEN): reverse-proxy/SSL and real-client-IP docs gaps.

Counterweight (§2): the same sweep found exceptional maintainer
responsiveness — multiple 11-day report-to-release cycles, proactive
self-filed DX issues, candid communication.

## 4. Reading the pattern

Three systematic causes explain nearly all of the above:

1. **Persona crossover.** Error messages and docs route personas into the
   wrong toolchain (compose error → bare-metal installer; production doctor →
   dev-tool warnings; maintainer's private config → contributor front door).
2. **The gates are wrong, not the machinery.** Version gates block versions
   that work (Node 22) while the floor that matters (Ruby 3.4, UTF-8 locale,
   `pnpm run build`, schemas) is unenforced and undocumented. Everything past
   the gates ran green on the first honest try.
3. **Correct answers exist but aren't promoted.** The Linux `--add-host` fix
   (CI), the compose SECRET one-liner (docker/README), admin creation (YAML
   comment), `node-version-file` (bump-api-docs.yml), test-account creation
   (test-accounts.md) — each already written, none reachable from the paths
   users follow. Reconciliation beats construction.

## Related

- [install-onboarding-work-chunks.md](./install-onboarding-work-chunks.md) —
  these findings packaged into shippable chunks
- [dev-onboarding-problem-space.md](./dev-onboarding-problem-space.md) —
  D-series recommendations for §3.4/§3.5
- [install-onboarding-testing-strategy.md](./install-onboarding-testing-strategy.md) —
  the harness that keeps every finding here fixed once fixed
- [install-onboarding-problem-space.md](./install-onboarding-problem-space.md) —
  operator-side strategy (R-series); its Phase 0 items map directly onto §3.1–3.3
- Issue #2628 — the maintainer's own prior gap analysis this audit extends
