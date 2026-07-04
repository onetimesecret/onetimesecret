---
title: Install & First-Run Onboarding — Problem Space and Recommendations
type: assessment
status: draft
updated: 2026-07-04
---

# Install & First-Run Onboarding: Problem Space and Recommendations

The initial setup experience is clunky enough that we receive complaints about
it. This document restates the problem space, surveys the documented approaches
(drawing on the March 2026 install-onboarding competitive landscape research:
Discourse, Coolify, Plane, Sentry Self-Hosted, GitLab Omnibus), and makes
prioritized recommendations. Issue #2700 ("Add a simple wizard that appears
precisely when it is meant to") is treated as one instance of a general class
of problem, not a one-off feature.

Recommendation IDs (R0.x–R3.x, N1–N3) are referenceable in follow-up issues.

---

## 1. The Problem Space — Three Distinct Problems

Complaints about "setup" conflate three problems with different owners,
different technical constraints, and different fixes. Naming them separately is
the first step to fixing any of them.

### P1 — Install-time friction (CLI tier)

Getting from clone/`docker run` to a booted instance. The current surface:

- **Config spread across four files plus env**: `.env` (`.env.example` is the
  10-var starting point; `.env.reference` documents ~116 vars),
  `etc/config.yaml` (the default is 1,157 lines with **217 ERB env-var
  interpolations**), `etc/auth.yaml`, `etc/logging.yaml`.
- **`SECRET` is high-stakes**: it must be generated, exported, and backed up
  manually in the Docker quick start (README), and losing it orphans all
  existing secrets. `rake ots:secrets` automates generation for the
  `install.sh` path, but the Docker path is copy-paste shell.
- **Preflight is partial**: `install.sh` checks Ruby/Node versions upfront but
  discovers a missing Valkey only late (the "install mark" step warns and
  skips), and the Docker path has no preflight at all.

### P2 — First-run configuration (web tier)

What happens after first boot. Today, nothing does — there is no first-run web
experience at all:

- **Creating the first admin requires shell access.** Colonel (admin) accounts
  are promoted exclusively via CLI: `bin/ots customers role promote EMAIL`
  (documented in `etc/defaults/config.defaults.yaml:263`). A web-only operator
  (e.g. running the container on a PaaS) has no path to an admin account
  without exec-ing into the container.
- **"Feature enabled but unconfigured" states dead-end.** #2700's subject:
  `AUTH_SSO_ENABLED=true` with no provider credentials silently yields no SSO
  buttons. SSO config is "install-time only — env vars set at deploy, read at
  boot" (`docs/authentication/per-install-sso.md:292`). The same shape applies
  to SMTP (unconfigured mail fails at first send, not at setup).
- **The admin UI can look but not touch.** `GET /api/colonel/config` returns
  masked config sections, but there is **no POST route**
  (`apps/api/colonel/routes.txt`) — even though the frontend already ships an
  `update()` action POSTing to `/api/colonel/config`
  (`src/shared/stores/systemSettingsStore.ts:58`). The write path is
  aspirational plumbing with no backend.

### P3 — Ongoing reconfiguration and diagnosis

- **Every config change is edit-file-and-restart.** `Onetime.conf` is loaded
  once (ERB → YAML → merge) and **deep-frozen** at boot
  (`lib/onetime/config.rb:540`). There is no runtime-config tier.
- **Containers run with a read-only filesystem**, so even "edit the file"
  isn't available in the deployment mode we recommend. This is the technical
  blocker #2700 names: *"we'll need to sort out a way to save env overlays to
  valkey or similar b/c running in a container with readonly disk."*
- **Diagnosis is thin.** `install.sh doctor` checks versions, Valkey ping, and
  file presence — a good foundation, but there's no shareable support bundle,
  so support threads start with "send me your logs and your config."

### The structural root

P2 and P3 share one root cause: **all configuration is bootstrap-tier.**
The landscape research found every studied project separates config into two
tiers:

| Tier | What goes here | Storage | Mutability |
|---|---|---|---|
| Bootstrap | DB credentials, secret keys, ports, external URLs | File / env var | Requires restart |
| Runtime | Site name, policies, feature toggles, branding, SMTP, SSO connections | Database | Hot-reloaded (or restart-applied) |

The dividing line: *if the app needs the value to boot, it's bootstrap; if it
needs it to behave correctly after boot, it's runtime.* OTS puts everything in
the bootstrap tier. `SITE_HOST`, `SECRET`, `VALKEY_URL` belong there — but
branding, TTL options, SMTP, SSO connection fields, and feature toggles are
runtime config trapped in boot-time files. Until a runtime tier exists, no
wizard has anywhere to write, and #2700 cannot be built except as a
throwaway.

---

## 2. What Already Exists (don't rebuild these)

The CLI tier is closer to the industry patterns than the complaints suggest:

| Asset | Where | Matches pattern |
|---|---|---|
| Re-runnable install with `auto`/`init`/`reconcile` modes | `install.sh` | Sentry's idempotent `./install.sh` |
| Auto-generated secrets, idempotent, with `DERIVE=1` re-derivation | `rake ots:secrets` | Coolify / Discourse secret generation |
| `doctor` command (versions, Valkey ping, file presence, auth-mode-aware) | `install.sh cmd_doctor` | Plane `prime-cli`, `gitlab-ctl check-config` (early stage) |
| First-run detection via Redis counter `onetime:install:init_count` | `lib/onetime/cli/install_command.rb` | "Database state" detection (Discourse/Mattermost family) |
| Read-only admin config view with secret masking | `GET /api/colonel/config` | The read half of a settings UI |
| Frontend settings store with fetch/update | `systemSettingsStore.ts` | The client half of the write path |
| Progressive-disclosure principle, already articulated | `docs/product/workspace-terminology.md` | Plane Express/Advanced philosophy |
| Onboarding empty-state dashboard | `DashboardEmpty.vue` (#2088) | First-session UX scaffolding |

The gaps, per the landscape feature matrix: interactive setup, web first-run
wizard, support bundle, CI-tested install, and config-surface consolidation.

---

## 3. The Gamut of Documented Approaches

### Bridging file config to a web wizard — three patterns

**Pattern A — "File boots, wizard configures"** (Discourse, PostHog,
Nextcloud). File/env config gets the app running with minimal values; the
first web visit detects virgin state (no admin user) and a wizard writes
everything else to the database. After the wizard, files are read-only.

**Pattern B — "File pins, UI defaults"** (Sentry; the landscape research calls
it the most elegant). File and UI manage overlapping settings. A value present
in the file **wins and is greyed out in the UI**; a value absent from the file
is freely editable in the UI (persisted to the database). Ops teams keep
config-as-code and automation; app admins get a UI without SSH. *The file is
the override; the database is the default.*

**Pattern C — "Web writes to files"** (WordPress, Gitea first-run). The web
installer writes config files to disk. **Disqualified for OTS**: it is the
documented anti-pattern precisely because of read-only container filesystems,
permission issues, and race conditions — the exact constraint #2700 names.

A and B compose: A describes the *first-run moment*, B describes the
*steady-state precedence rule*. That composition is what we should build.

### First-run detection

| Approach | Used by | Mechanism |
|---|---|---|
| File existence | WordPress | Does the config file exist? |
| Flag in config | Gitea (`INSTALL_LOCK`), Nextcloud | Boolean sentinel |
| Database state | Discourse (no admin), Mattermost (no users) | Query sentinel data |
| External script only | Mastodon, GitLab, Sentry | CLI init; no web wizard |

The robust approach combines two signals. OTS already has the Redis init
counter (database-state pattern); adding "no colonel account exists" as the
second signal gives WordPress-grade robustness.

### CLI-tier patterns (from the ranked competitor analysis)

- **Preflight checks** (Sentry, the strongest): validate dependencies, RAM,
  ports *before touching anything*.
- **Interactive setup** (Discourse, the benchmark): 3–5 questions, generate
  everything else. First web visit is a setup wizard.
- **Doctor/repair** (Plane `prime-cli`, `gitlab-ctl`): healthcheck, repair,
  monitor as first-class verbs.
- **Support bundle** (Mattermost `mmctl system supportpacket`): sanitized,
  shareable diagnostic archive.
- **Single config surface** (GitLab `gitlab.rb`; Plausible: 3 env vars).
- **Opinionated single path** (Discourse: Docker only). OTS deliberately
  supports Docker + bare-metal; that trade (more surface, more flexibility)
  is not revisited here.

### Testing & measurement

- **The install script is a product, not a utility** — the landscape's key
  insight. Sentry runs `./install.sh` from scratch in CI *twice daily* across
  x86/ARM and Docker/Podman, then runs pytest HTTP assertions against the live
  instance. GitLab runs nightly full E2E on package builds.
- Tiers: ShellCheck (static) → BATS (unit-test shell functions like
  `check_version`, `is_initialized`) → Goss/Testinfra (post-install system
  state). Goss is the standout for fresh-install validation: single Go binary,
  YAML assertions, can serve results as a health endpoint.
- **TTFHW ("time to first hello world") and the 15-minute rule**: clone →
  running service → first secret shared, under 15 minutes, or people leave.
- Funnel instrumentation (PostHog self-hosted), step-numbered exit codes in
  install scripts to locate abandonment, opt-out telemetry following
  Homebrew's model (`DO_NOT_TRACK`, first-run disclosure, OS/arch/version/
  success-failure only).

---

## 4. Recommendations

Phased so that each phase pays for itself; Phase 1 is the architectural
keystone the others depend on.

### Phase 0 — Stop the bleeding (no architecture change)

**R0.1 — CI-tested install.** A scheduled GitHub Action that runs
`install.sh` (and `docker compose up`) in a fresh container, then asserts via
HTTP: health endpoint responds, a secret can be created and revealed through
the API. ShellCheck on `.sh` files in CI; BATS tests for `install.sh`
functions (`check_version`, `redis_url`, `auth_mode` are pure and trivially
testable). Rationale: some fraction of "clunky install" complaints are
regressions nobody notices because nothing exercises the fresh-install path.
This is the cheapest permanent insurance, and the landscape's top
recommendation for OTS verbatim.

**R0.2 — Support bundle: `install.sh doctor --bundle`.** Extend the existing
`cmd_doctor` to emit a sanitized, shareable diagnostic archive: versions,
which config files exist, auth mode, Valkey reachability, env var *presence*
(names only, never values), recent boot log excerpt. Directly attacks the
support back-and-forth that today starts every complaint thread.

**R0.3 — Complete the preflight.** Move the Valkey reachability check to the
*front* of `cmd_init` (it currently surfaces at the final "install mark"
step), and check port availability. Fail fast with a one-line fix suggestion,
Sentry-style.

### Phase 1 — Runtime-config overlay in Valkey (the keystone)

This is the direct answer to #2700's blocker and the precondition for any
wizard. It is additive: nothing about `.env`/YAML changes.

**R1.1 — Define the tier split.** Classify every config key as bootstrap
(`SECRET`, `VALKEY_URL`, `HOST`, ports, database URLs — never overlay-able) or
runtime (SMTP/emailer, SSO provider connection fields, branding, TTL/secret
options, feature toggles, interface settings). The colonel
`GetSystemSettings` sections are a ready-made starting taxonomy.

**R1.2 — Overlay storage + merge point.** A Familia-backed settings hash
(e.g. `onetime:config:overlay`) merged at a single defined point in config
loading: `defaults → YAML(ERB+env) → runtime overlay`, **with Sentry's
"file pins" precedence**: if a key is explicitly set via env/YAML, the file
value wins and the overlay is ignored; the admin UI renders that field
read-only with a "set by environment" affordance. Ops keeps config-as-code;
PaaS operators get a UI. Valkey is already the durable runtime store for
everything else (customers, metadata), so this extends existing
infrastructure rather than adding a new dependency — and it survives container
restarts, which the read-only disk cannot offer.

**R1.3 — Apply semantics: restart-required first, hot-reload later.** Phase
1a: the overlay is read once at boot into the deep-frozen `Onetime.conf` —
changes require restart, but are *persistent and web-editable*, which already
unblocks the wizard. Phase 1b (optional, later): a generation counter /
pub-sub bump for hot-reloading keys that are safe to change live. Do not let
hot-reload complexity delay 1a.

**R1.4 — Implement `POST /api/colonel/config`.** The route missing from
`apps/api/colonel/routes.txt`, with per-section schema validation and
write-only semantics for secrets (masked values round-trip as "unchanged").
The frontend store's `update()` already targets this endpoint.

### Phase 2 — First-run web wizard (the Pattern A moment)

**R2.1 — Detection.** Combine the existing `onetime:install:init_count`
counter with a database-state check ("no colonel exists") — the two-signal
approach the landscape identifies as most robust.

**R2.2 — First-admin creation without SSH.** When the wizard state is
detected, allow creating the first colonel account through the web — gated by
a one-time setup token printed to stdout/logs at first boot (the
Jenkins/Portainer pattern), so an unattended instance exposed to the internet
cannot be claimed by a stranger. `bin/ots customers role promote` remains for
ops and scripting.

**R2.3 — Wizard steps, progressively disclosed.** Simple mode: (1) create
admin, (2) confirm detected host/SSL (bootstrap-tier: display-only), (3) SMTP
with a test-send button (runtime tier, writes overlay), (4) done → dashboard.
Advanced sections (SSO, branding, TTL policy) are present but skippable —
Plane's Express/Advanced split, and consistent with the progressive-disclosure
principle already established in `workspace-terminology.md`.

**R2.4 — #2700 becomes a special case, not a one-off.** "SSO enabled without
connection settings" is one instance of *feature enabled but unconfigured*.
Build the general mechanism: a config-completion prompt component that (a)
detects the state, (b) renders the relevant wizard section in the colonel
area, (c) writes through the same overlay path. SMTP-unconfigured gets the
same treatment for free. The wizard "appears precisely when it is meant to"
because appearance is driven by detected config state, not by routing
special-cases.

### Phase 3 — Surface consolidation and measurement

**R3.1 — Interactive `install.sh init`.** 3–5 Discourse-style prompts (host,
auth mode, SMTP now-or-skip), writing `.env`; defaults for everything else.
The non-interactive path (`--yes` / env-var-driven) stays first-class for
automation.

**R3.2 — Stop growing the config surface.** Direction, not big-bang: document
env vars as the primary operator interface with `.env.example` (10 vars) as
the canonical quick start and `.env.reference` (~116 vars) as the complete
catalog; treat YAML as the advanced/derived layer. New settings should default
to the runtime tier (overlay) unless they are genuinely bootstrap.

**R3.3 — Measure.** Step-numbered exit codes in `install.sh` so failures
report *which* stage died; TTFHW as the metric for the quick start (target:
under 15 minutes, measured honestly from `git clone`/`docker run` to first
secret shared); docs feedback widgets on install pages. Opt-out telemetry
(Homebrew model, `DO_NOT_TRACK`-respecting) only if/when we decide the
privacy trade is acceptable for this product's audience — for a secrets
product this deserves explicit discussion, not a default.

### What NOT to do

**N1 — No web-writes-to-files (Pattern C).** Disqualified by the read-only
container filesystem; it is the documented industry anti-pattern.

**N2 — No overlay for bootstrap keys.** `SECRET`, database/queue URLs, host
and ports stay env/file-only. A UI that can change the values the app needs
to boot is a footgun (and a lockout risk).

**N3 — Don't build #2700 as a bespoke SSO-only flow before Phase 1.** Without
the overlay it would have to write somewhere ad hoc, creating a parallel
persistence path we'd have to unwind. The wizard is a week of UI once the
overlay exists; the overlay is the actual work.

---

## 5. How This Maps to the Complaints

| Complaint shape | Addressed by |
|---|---|
| "Too many knobs before anything works" | R3.1 (interactive init), R3.2 (env-first surface), R2.3 (wizard defaults) |
| "I need SSH/exec just to make myself admin" | R2.2 (web first-admin with setup token) |
| "I enabled X and nothing happened" | R2.4 (config-completion prompts; #2700) |
| "Every change means editing files and restarting, and my container disk is read-only" | R1.1–R1.4 (Valkey overlay + colonel write path) |
| "Install failed and support ping-pong took days" | R0.2 (support bundle), R0.3 (preflight), R3.3 (staged exit codes) |
| "It broke on the new release" | R0.1 (CI-tested install) |

## Related

- Issue #2700 — SSO configuration wizard (the trigger for this assessment)
- Issue #2088 — `DashboardEmpty.vue` onboarding state (shipped)
- Issue #2308 — workspace creation-surface plan (stale/closed; adjacent UX)
- `docs/product/workspace-terminology.md` — progressive-disclosure principle
- `docs/authentication/per-install-sso.md` — current env-only SSO configuration
- Install-onboarding competitive landscape research (March 2026) — source for
  the patterns, competitor matrix, and testing/measurement guidance cited here
