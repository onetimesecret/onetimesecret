---
title: Install Onboarding — Clean-Slate Testing Strategy
type: strategy
status: draft
updated: 2026-07-09
---

# Install Onboarding: Clean-Slate Testing Strategy

How to test the install and dev-onboarding experience when every maintainer
machine is a poisoned well — accumulated config (`~/.config/onetimesecret-dev`,
direnv, overmind, Caddy webroots, UTF-8 locales, correct tool versions) that
masks what fresh users actually experience.

Companion to [install-onboarding-problem-space.md](./install-onboarding-problem-space.md)
(R0.1 "CI-tested install" is expanded here into a concrete harness design) and
[install-onboarding-current-state.md](./install-onboarding-current-state.md)
(the defects this strategy would have caught). The March 2026
[landscape doc](./install-onboarding-landscape.md) already covers the tooling
tiers (ShellCheck, BATS, Goss/Testinfra) and Sentry's twice-daily CI installs;
this doc goes beyond it: the *maintainer-local* clean-room story, devcontainers
as test rigs, macOS coverage, compose-path mechanics, and drift guards — all
verified against primary sources in July 2026.

## 0. The organizing principle

Every project with a strong onboarding reputation (Zulip, Mastodon, Pi-hole,
Homebrew, GitLab GDK) converged on the same move:

> **The documented setup command and the CI-executed command are the same
> artifact, and it runs from zero somewhere, on every change.**

Zulip's CI runs `tools/provision` (the documented contributor command) in five
fresh distro containers on every PR — then runs it a *second* time to prove
idempotency ([zulip-ci.yml](https://github.com/zulip/zulip/blob/main/.github/workflows/zulip-ci.yml)).
GDK's CI installs itself using the literal `curl | bash` one-liner from its own
docs, pinned to the MR's SHA ([Dockerfile.verify](https://gitlab.com/gitlab-org/gitlab-development-kit/-/blob/main/support/ci/Dockerfile.verify)),
then runs `doctor`, `update`, and `pristine` against the result. Homebrew's
installer repo executes `/bin/bash -c "$(cat install.sh)"` on macOS, Ubuntu,
and WSL, then asserts one real operation (`brew install ack`) — not output text
([tests.yml](https://github.com/Homebrew/install/blob/master/.github/workflows/tests.yml)).

The corollary for us: `install.sh`, `install-dev.sh`, and the compose quick
start are products. Until something executes them from zero, every release is
an untested release of our most-viewed feature. The cautionary tales are real:
Coolify's `curl | bash` installer — their #1 funnel — has **no CI test at all**
(verified by absence in `.github/workflows/`); docker-install ships lint-only
verification and a "not recommended for production" disclaimer.

### What clean-slate testing would have caught here

Empirical first-run traces in a fresh Linux container (this repo, July 2026 —
transcripts summarized in
[install-onboarding-current-state.md](./install-onboarding-current-state.md)):

| Defect found in ~30 min of clean-room runs | Would be caught by |
| --- | --- |
| README compose quick start dies at `${SECRET:?}` interpolation | Tier 2a compose smoke (any run) |
| `install.sh init` dies "Node too old: have 22, need 25+" — CI itself builds on 22 | Tier 1 harness / Tier 2b installer matrix |
| Gemfile floor `>= 3.3.6` is false — kanayago gem needs Ruby 3.4+ | Tier 1 harness on a `ruby:3.3` image |
| `rake ots:secrets` and puma boot **crash on machines without a UTF-8 locale** (Unicode box-drawing in `.env.example` comments + UTF-8 in `config.ru`; `Encoding::CompatibilityError` under `LANG=` / POSIX locale — i.e. minimal Debian/Ubuntu servers, containers, systemd units) | Tier 1 harness (containers have no locale by default — the clean room *is* the repro) |
| Bare-metal path boots but serves an assetless UI; only a server-side log line says `Run pnpm run build` | Tier 2c proof-of-life assertion (asset URL check, not just `/api/v2/status`) |

None of these reproduce on a maintainer workstation. All of them reproduce in
any fresh container. That asymmetry is the entire argument for this strategy.

## 1. The test matrix

Five install surfaces × the environments that can honestly exercise them:

| Surface | Persona | Clean-room environment | Tier |
| --- | --- | --- | --- |
| `docker run` quick start (README) | docker-selfhoster | CI ubuntu runner; any docker host | 2a |
| `docker compose up` | compose-selfhoster | CI ubuntu runner; local `--renew-anon-volumes` | 2a |
| `install.sh` bare-metal | baremetal-selfhoster | pinned-image containers (local + CI) | 1, 2b |
| `install-dev.sh` + `bin/dev` | contributor | devcontainer; macOS runner; local harness | 2b, 3 |
| `install-test.sh` → suites | contributor/CI | fresh-clone CI job (this is the Zulip shape) | 2c |

## 2. Tier 1 — Local clean-room harness (run it from a poisoned machine)

The direct answer to "how do I experience a fresh install from my own laptop."
Pattern verified in Pi-hole ([test/run.sh](https://github.com/pi-hole/pi-hole/tree/master/test) —
per-distro Dockerfiles, BATS suites, a dedicated fresh-install suite in a
container that's allowed to mutate the filesystem), netdata (copy-pasteable
`docker run -v $PWD:/netdata -w /netdata ubuntu:latest sh -x .../run-updater-check.sh`),
and nvm (a README-documented dev/test container).

**Minimal viable version (a day):** `scripts/test-install/run.sh`

```bash
# Shape, not final code. Each path gets a stage; each stage is one
# `docker run --rm` against a PINNED base image with the repo mounted
# read-only and copied inside (never bind-mount your working tree writable —
# and never your caches; `git archive HEAD | docker run -i ...` or an
# in-container `git clone /src` keeps host state out).
docker run --rm -i ruby:3.4-slim bash -s <<'EOF'
  set -e
  # ... apt-get install nodejs/pnpm per pinned versions, git clone /src app ...
  ./install.sh init
  # post-conditions, not exit codes alone:
  test -s .env && grep -qE '^SECRET=.{32,}' .env
  ./install.sh init          # second run: idempotency is a test, not a hope
EOF
```

Key mechanics from the verified implementations:

- **Pinned base images per lane**: `ruby:3.4-slim` (documented floor),
  `ruby:3.3-slim` (should fail *with a clear message* — a lane can assert an
  error is good), `debian:12-slim` + rbenv (the "user installs Ruby themselves"
  lane), `ubuntu:24.04`. Pi-hole names these `_debian_12.Dockerfile` etc. and
  `--distro` selects one.
- **Scrub inherited state explicitly**: angristan/openvpn-install runs its
  installer with `env -u HOME`; `brew test-bot --local` redirects `$HOME` into
  `./home/`. Containers give you most of this for free — which is the point.
- **Test outcomes, not exit codes**: angristan spins up a *client* container
  that actually connects with the produced `client.ovpn`. Our equivalent:
  create a secret via the API and retrieve it once (see §4 proof-of-life).
- **`docker diff` as a cheap assertion**: enumerate every file the installer
  touched; fail if it wrote outside its documented footprint.
- **Idempotency re-run**: Zulip and Rails `bin/setup` ("This script is
  idempotent, so that you can run it at any time and get an expectable
  outcome") both treat second-run-clean as a contract.
- **No expect/tmux for prompts**: no major project drives installer prompts
  with expect in CI (verified by absence). The norm is a headless mode
  (`NONINTERACTIVE=1` in Homebrew's installer) and testing *that*. If
  `install.sh` ever grows prompts (problem-space R3.1), the flag comes first.
- **Locale honesty**: do NOT set `LANG` in the harness images. The default
  POSIX locale of containers is representative of fresh servers — it found the
  `Encoding::CompatibilityError` boot crash.

**Week version:** per-distro Dockerfiles + BATS post-condition suites
(the landscape doc's BATS recommendation, now with a concrete template:
Pi-hole's `test_fresh_install.bats`), openHABian's naming convention for
safety tiers (`unit-*` runs anywhere, `destructive-*` only ever in the
container), and a `--lane` flag selecting docker-run/compose/baremetal/dev.

Because the harness is a script in the repo, CI runs the *same artifact*
(Tier 2) — local and CI cannot diverge.

## 3. Tier 2 — CI jobs

### 2a. Compose/docker smoke (the #1 funnel)

Verified reference implementations: Supabase smoke-tests its documented
self-host compose with **published pinned images** on every PR touching
`docker/**` ([self-host-tests-smoke.yml](https://github.com/supabase/supabase/blob/master/.github/workflows/self-host-tests-smoke.yml));
Sentry runs its literal `./install.sh` install path **4×/day on a cron**, so
registry-side breakage is caught with no commit at all
([test.yml](https://github.com/getsentry/self-hosted/blob/master/.github/workflows/test.yml));
Immich's flags are the state hygiene to copy
(`up -d --renew-anon-volumes --force-recreate --remove-orphans --wait --wait-timeout 300`,
logs dumped as artifact on failure); Mattermost validates every documented
file combination with `docker compose config` as a zero-cost lint job first.

The job shape for us:

```
docker compose config -q                          # lint (simple AND full include combos)
docker compose up -d --quiet-pull --wait --wait-timeout 180 \
  --renew-anon-volumes --force-recreate
<proof-of-life: §4>
docker compose logs --no-color   # in an `if: always()`/`failure()` step
docker compose down -v
```

Mechanics that matter (all primary-source verified):

- `--wait` exits nonzero if any service never reaches running|healthy — it is
  the readiness assertion. **Prerequisite: the app service needs a real
  `healthcheck`** (today only `maindb` has one in
  `docker/compose/docker-compose.simple.yml`; the app relies on
  `docker/entrypoints/healthcheck.sh` in the image — wire it into compose).
- `depends_on: {condition: service_healthy}` for Valkey, not sleeps: "Compose
  does not wait until a container is 'ready', only until it's running"
  (Docker's own startup-order doc).
- `start_interval` for fast startup polling needs Compose ≥ 2.20.2 *and*
  Engine ≥ 25 — fine in CI, don't make documented files depend on it.
- Known trap: a one-shot service with no dependents makes `up --wait` exit 1
  on success (docker/compose#10596, open) — if compose ever grows a migration
  container, the app must `depends_on` it.
- Healthchecks must exec something the image ships (distroless/slim images
  silently fail every probe and `--wait` times out with a misleading error).
- Two lanes: PR lane builds/pulls HEAD-ish images; **scheduled lane runs the
  README's verbatim commands against the published `:latest` AND the pinned
  tag the README shows** (`v0.24.6` today). Nothing else catches "the docs
  reference a broken/missing tag." This is problem-space R0.1, made concrete.
- Renovate/Dependabot both support compose files now; pinned-tag bumps arrive
  as PRs, which the smoke lane then validates.

Also run the `docker run` one-liner from the README verbatim as its own step —
Supabase and Sentry both test the *documented* path, not an idealized one.

### 2b. Installer matrix (bare-metal + dev scripts)

Verified references: tailscale runs `scripts/installer.sh` in **~22 distro
containers** on a daily cron + path-filtered PRs
([installer.yml](https://github.com/tailscale/tailscale/blob/main/.github/workflows/installer.yml));
chezmoi tests the actual `sh -c "$(curl ...)"` piped invocation, path-filtered
with `dorny/paths-filter`; ohmyzsh gates deployment of its installer on the
macOS+Linux test job passing.

For us: a path-filtered `installer.yml` that fires on changes to
`install*.sh`, `bin/dev`, `lib/tasks/init.rake`, lockfiles, or the workflow
itself, plus a weekly cron:

- **Linux lanes**: invoke the Tier 1 harness (`scripts/test-install/run.sh
  --lane baremetal --distro ruby34`, etc.). One lane deliberately uses a
  POSIX locale, one `ruby:3.3` (expect the documented failure).
- **One `runs-on: macos-15` lane** executing `bash install-dev.sh` and
  `./install-test.sh`. This is the only honest test of stock **bash 3.2 +
  BSD userland** — a Linux container cannot simulate BSD sed/grep/readlink.
  Free on public repos. Caveat (verified): the runner image is itself a
  poisoned well (Homebrew, Node, Ruby preinstalled) — it answers "does the
  script's *code* run on macOS," not "does dependency discovery work on a
  fresh Mac." Homebrew's trick when that matters: an explicit
  `/bin/bash -u -n script.sh` syntax gate under 3.2, and scrubbing
  preinstalled tools before the real test.
- **bash-3.2 cheap gate on Linux**: run the scripts' syntax/function tests in
  the official `bash:3.2` image (bats-core's own version-matrix pattern) —
  catches bashisms without macOS minutes; misses BSD userland (that's the
  macOS lane's job). Note `install-dev.sh` currently *requires* bash 4+ by
  design; the gate then asserts the version check itself fails gracefully.
- Runner-image churn is real: macos-13 retired Dec 2025, macos-14 unsupported
  Nov 2026 — pin matrix entries deliberately and expect an annual bump.
- For genuinely pristine macOS (rarely needed): Cirrus Labs `tart` with the
  `macos-*-vanilla` images on any Apple Silicon machine — one-time ~25 GB
  base pull, then per-run APFS copy-on-write clones in seconds
  (`tart clone base t1 && tart run t1` … `tart delete t1`). Status note
  (2026): Cirrus CI the hosted service shut down June 2026 and the team
  joined OpenAI; tart the tool remains available under FSL (free for internal
  use). Apple's EULA caps 2 concurrent macOS VMs/host — irrelevant for
  serial solo use. Lima covers the inverse (fresh Linux VM on a Mac) for
  free. Do not build a Mac mini CI fleet; this is what hosted runners and
  tart clones are for.

### 2c. Fresh-clone contributor job (the Zulip shape)

A CI job that is *nothing but the documented contributor path*:

```
fresh runner → ./install-test.sh → pnpm run test:rspec:fast && pnpm test
             → ./install-test.sh   # second run = idempotency check (Zulip)
             → git status --porcelain | wc -l == expected   # litter check (Zulip)
```

If this job needs any step the docs don't state, either the job or the docs is
wrong — fix one. (Empirically, `install-test.sh` already survives a clean fork
in ~76s on warm caches with correct Ruby — it is the closest existing artifact
to `bin/setup` and the natural spine for this job.) Cache pnpm store and gems
keyed on lockfiles; Zulip's caches are designed so a cached run installs
exactly what an uncached run would.

The job's **duration is the TTFHW proxy** for the contributor path (the
landscape doc's 15-minute rule): chart it, alarm on regression. Publishing
"fresh clone → green suite" as a tracked CI metric appears to be genuinely
uncommon (no verified prior art) — cheap novelty worth having.

A 10-line drift guard closes the docs loop: grep README/docs for each
documented command (`./install.sh init`, `bin/dev`, `pnpm run test:rspec:fast`)
and fail if a referenced script/target no longer exists. Full docs-execution
frameworks (runme, byexample, tesh, clitest, mdsh) are anti-recommended: all
bus-factor-1 or dormant, and doctest-style output matching rots on
timestamps/versions. Keep docs commands thin; CI-test the scripts they call.

## 4. Proof-of-life: the standard assertion

Every lane ends the same way — behavior, not logs (log-text asserts are
brittle and none of the verified projects use them):

1. `GET /api/v2/status` → 200 (already exists, empirically verified working).
2. `GET /` → 200 **and the referenced `/dist/assets/*.js` returns 200** — the
   status endpoint alone said "nominal" while the UI was assetless; asset
   round-trip is the check that would have caught it.
3. API round-trip: create a secret, retrieve it once, second retrieval fails
   (the product's core invariant as a smoke test).

Package this once as `scripts/test-install/proof-of-life.sh <base-url>` so
Tier 1, 2a, 2b, 2c, and any future Goss spec (landscape doc §3) all call the
identical assertion. `curl --fail --retry 10 --retry-connrefused` is the
retry idiom; [hurl](https://github.com/Orange-OpenSource/hurl) is the upgrade
path if the API assertions grow.

## 5. Tier 3 — Devcontainer as both the fix and the rig

The keystone pattern (verified): Mastodon's devcontainer runs
`"postCreateCommand": "bin/setup"` — **every devcontainer/Codespace launch is
a fresh execution of the contributor setup path**, so it cannot silently rot;
Rails goes further and smoke-tests generated devcontainers on every push via
`devcontainers/ci` ([devcontainer-smoke-test.yml](https://github.com/rails/rails/blob/main/.github/workflows/devcontainer-smoke-test.yml));
velocitas adds a **nightly cron** so upstream image/feature rot is caught with
no commits.

For us (compose-based, mirroring Mastodon's layout; app + Valkey services;
`postCreateCommand: ./install-dev.sh` once that script survives a clean
machine — see dev-onboarding D-series):

- The devcontainer *is* the maintainer's disposable clean room: Codespaces in
  the cloud, or the same `devcontainer.json` locally via `@devcontainers/cli`
  (`devcontainer up`) or plain Docker. This remote session's container — where
  all the empirical findings reproduced in minutes — is the same idea already
  working for us; a devcontainer makes it deliberate, versioned, and shared
  with contributors.
- Keep it honest with one loud workflow: `devcontainers/ci@v0.3` with
  `runCmd: ./install-test.sh && pnpm run test:rspec:fast`, path-filtered on
  `.devcontainer/**` + install scripts + lockfiles, plus weekly cron; push the
  image to GHCR as a build cache. Codespaces prebuilds rebuild on every push
  but their failure notifications are opt-in and quiet — they are not the
  alarm.
- Base images: `ghcr.io/rails/devcontainer/images/ruby` is maintained
  upstream — don't hand-roll a Dockerfile that becomes a second rot surface.
- Honest costs (verified): Home Assistant — the heaviest devcontainer user in
  OSS — ships a documented recovery procedure for stale containers; Discourse
  routes node_modules and datastore dirs through named volumes because
  bind-mount I/O on Apple Silicon is slow. Never *mandate* the devcontainer
  (heavy images push away drive-by doc-fix contributors); it's the guaranteed
  path, not the only path.
- Don't add `.gitpod.yml` (platform sunset Oct 2025); don't build the workflow
  on DevPod (maintenance stalled — fine as an optional local runner since the
  durable artifact is `devcontainer.json` itself).

## 6. Tier 4 — Pins + doctor = diff(manifest, reality)

Drift *prevention* so the clean-room tests fail less often, and diagnosis for
everyone's machine. All verified:

- **Single-source the versions**: `.ruby-version` (missing today — `install.sh`
  and `ci.yml` already reference it) and `.node-version`. CI consumes them
  natively: `ruby/setup-ruby` auto-reads `.ruby-version` → `.tool-versions` →
  `mise.toml`; `actions/setup-node` has `node-version-file`. The Gemfile line
  becomes `ruby file: ".ruby-version"` — one line, enforced on every `bundle`
  invocation, and it retires the currently-false `>= 3.3.6` floor. A 5-line CI
  grep asserts the Dockerfile's ARG matches the pin files (the Dockerfile is
  the unavoidable third copy).
- **pnpm pins itself**: with pnpm 11, `packageManager` + `engines.node` in
  package.json are enforced by pnpm directly (`pmOnFail` defaults to
  `download`; project-level `engines` violations always fail install). Do not
  build on corepack — Node's TSC voted (2025) to stop distributing it in
  Node 25+.
- **mise** (`mise.toml` or keeping `.tool-versions`) is the recommended local
  converger — GDK made it their default and dropped asdf entirely in 2025.
  Committed mise.toml is still early-adopter territory among top OSS repos;
  the pin *files* are the portable artifact, mise is one consumer. Do not
  combine direnv and mise for PATH (explicitly unsupported upstream); direnv
  stays for env vars only — which is how the repo already uses it.
- **Doctor reads, never restates**: extend `install.sh doctor` (or `bin/ots
  doctor`) on the GDK model — ~40 small checks, `--correct` for trivial fixes.
  Every check must be diff(declared file, live reality) or a live probe
  (Valkey PING, `redis-server --version` parse — GDK literally ships a
  "Valkey masquerading as Redis" check, the mirror of our Valkey-first
  stance; port-in-use; env-var presence). A doctor that hand-restates version
  numbers is a third copy of the manifest and will rot; prune any check that
  ever false-positives, or contributors learn to ignore it (`brew doctor`'s
  own docs say "just ignore this" — that's the failure mode). `bundle doctor`
  already exists for the broken-native-extensions class; doctor can shell out
  to it.
- **Nix/devenv/flox: anti-recommended** as a first move for a solo
  Ruby+Node maintainer. The hermeticity is real; so are native-extension
  pain, macOS quirks, and near-zero contributor familiarity. mise +
  devcontainer captures ~80% at ~10% of the cost. devenv.sh is the entry ramp
  if hermeticity is ever wanted (it can read `.ruby-version`).

## 7. Adoption order (leverage ÷ ongoing cost, solo-maintainer budget)

1. **Compose smoke script + PR/cron CI lanes** (§3.2a) — one ~15-line script,
   tests the #1 user funnel, near-zero maintenance. Prereq: app healthcheck in
   compose. *A day, including the healthcheck.*
2. **Tier 1 local harness, one distro lane** (§2) — the literal answer to the
   poisoned-well problem; the same script becomes CI's installer matrix
   (§3.2b). *A day for one lane; a week for the matrix + BATS post-conditions.*
3. **Fresh-clone contributor job** (§3.2c) — `install-test.sh` already nearly
   is this; wire it, add the idempotency re-run and litter check, chart the
   duration. *A day.*
4. **Pins + Gemfile `ruby file:` + CI reads pins + doctor extensions** (§6) —
   converts "works on my machine" from a debugging session into a one-command
   diagnosis. *A day for pins; a week including doctor work.*
5. **Devcontainer + devcontainers/ci weekly** (§5) — highest structural
   leverage (fixes the well and tests it with one artifact) but depends on
   `install-dev.sh` surviving a clean machine first (D-series). *A day for the
   container, a week including CI, after the D-series prereq.*
6. **macOS lane** (§3.2b) — an hour of YAML once the harness exists; catches
   the bash-3.2/BSD class nothing else can.

Deliberately not adopted: expect-driven prompt testing, docs-execution
frameworks, Nix, testcontainers for the install path (bash + `--wait` + curl
is sturdier and tests the exact artifact users run), Mac hardware fleets,
`.gitpod.yml`, corepack, log-text assertions, `sleep`-based readiness.

## Related

- [install-onboarding-problem-space.md](./install-onboarding-problem-space.md) —
  R0.1 (CI-tested install), R0.3 (preflight), R3.3 (measurement) are the
  strategic parents of this doc
- [install-onboarding-landscape.md](./install-onboarding-landscape.md) —
  ShellCheck/BATS/Goss tiers, Sentry case study, TTFHW/15-minute rule
- [install-onboarding-current-state.md](./install-onboarding-current-state.md) —
  the empirically-found defects referenced throughout
- [dev-onboarding-problem-space.md](./dev-onboarding-problem-space.md) —
  D-series recommendations this strategy's Tiers 2c/3 depend on
