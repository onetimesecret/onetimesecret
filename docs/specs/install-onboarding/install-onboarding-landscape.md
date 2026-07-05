---
title: Install Onboarding — Competitive Landscape
type: reference
status: current
updated: 2026-03-15
---

# Install Onboarding: Competitive Landscape

Tools, techniques, and patterns used by open-source commercial projects with
self-hosting capabilities to test, validate, and systematically improve their
installation and onboarding experience.

> Converted from the internal research memo (PDF, compiled March 2026) so the
> sources cited by
> [install-onboarding-problem-space.md](./install-onboarding-problem-space.md)
> are checkable in-repo. Content is reproduced faithfully; only formatting was
> adapted to Markdown.

|              |                                                                                 |
| ------------ | ------------------------------------------------------------------------------- |
| Feature area | Install / onboarding experience for self-hosted open-source commercial projects |
| Competitors  | Discourse, Coolify, Plane, Sentry Self-Hosted, GitLab Omnibus                   |
| Focus        | Install UX patterns, testing/validation approaches, measurement techniques      |
| Context      | Product strategy for OTS install experience improvement                         |

## 1. The Core Metric: Time to First Value

The dominant measure is TTFHW (Time to Hello World): how long from first
contact to a working instance. The industry benchmark is the **15-minute
rule**: if your tool doesn't deliver value in 15 minutes, people leave. For
OTS, that means: clone/download, running service, first secret shared.

| 15 min                  | TTFHW          | 3                    |
| ----------------------- | -------------- | -------------------- |
| Industry TTFV benchmark | Primary metric | Steps to first value |

Sixteen Ventures and Monetizely define TTFV as `Date_of_First_Value` minus
`Signup_Date`. The DX Core 4 framework (from the DORA/SPACE researchers)
combines perception data (surveys) with system metrics. Their "Time to First
Hello World" (TTFHW) metric is the developer-facing analog of TTFV.

## 2. Testing & Validation

Shell script testing has three tiers, each serving a different purpose:

| Tier                | Tool                                             | What it validates                                                         |
| ------------------- | ------------------------------------------------ | ------------------------------------------------------------------------- |
| Static analysis     | ShellCheck                                       | Syntax, quoting, portability bugs. Universal, should be table stakes.     |
| Unit testing        | BATS (bash-only) or ShellSpec (all POSIX shells) | Individual functions: `check_version`, `is_initialized`, `install_gems`   |
| Integration testing | Testinfra (Python/pytest) or InSpec (Ruby)       | Post-install system state: services running, ports listening, files exist |

All three integrate with Molecule for testing Ansible roles against multiple
OS targets.

### Case study: Sentry Self-Hosted

Sentry self-hosted is the gold standard for CI-testing install scripts:

- Twice-daily scheduled runs of `./install.sh` from scratch on fresh runners
- Matrix across x86 + ARM, Docker + Podman
- Pytest integration tests against the live instance after install (HTTP
  requests, login flows)
- ShellCheck on changed `.sh` files only, with GitHub Actions annotations
- Sandbox-based unit tests: clone repo to tmpdir, symlink working changes, run
  assertions

GitLab Omnibus takes a different approach: nightly package builds trigger
downstream QA pipelines that spin up HA instances and run the full E2E suite.

## 3. Infrastructure & Tooling Landscape

### Infrastructure state validation

Three tools dominate post-install verification, each testing whether a
machine/container actually has the expected packages, services, ports, files,
and users:

**Goss** is the standout for self-hosted install validation. Single Go binary,
no runtime deps, YAML-based assertions, and it can serve its test results as a
health endpoint. You can auto-generate initial test specs from a running
system's current state, then refine. The zero-dependency story matters when
testing fresh installs on customer machines.

**Testinfra** is the Python/pytest equivalent. Stronger if your config
management is Ansible-based since it reads Ansible inventory directly. Can
target local, SSH, Docker, or kubectl backends.

**Serverspec** is the Ruby/RSpec version. Mature but heavier dependency
footprint. Less common in new projects.

### Install script testing

**BATS** (Bash Automated Testing System) is the standard for testing
shell-based install scripts. TAP-compliant, works with CI, and pairs with
ShellCheck for static analysis. The pattern: ShellCheck catches
syntax/portability issues, BATS validates runtime behavior.

### CI smoke testing across OS/arch matrix

The Docker smoke testing pattern catches install regressions by spinning up
the built artifact and running assertions against it. GitHub Actions matrix
strategies let you test across Ubuntu variants, ARM/AMD64, and different
dependency versions in parallel. The key insight from CircleCI's writeup is
running these against the final published artifact, not an intermediate build
state.

### Documentation quality

**Vale** is the docs linter. Open source, CLI-based, enforces custom style
guides as code. GitLab and Datadog both run it in CI against their
install/setup docs. The docs-as-code approach means your install guide gets
the same PR review, linting, and testing pipeline as application code.

### Self-hosted product analytics

**PostHog** is the obvious choice for self-hosted analytics that can
instrument onboarding funnels. MIT-licensed, includes funnel analysis, session
replay, feature flags, and A/B testing. You define your onboarding milestones
as events, build funnels to see where people drop off, and use session replay
to understand why. Scales to ~100k events/month self-hosted before they
suggest cloud.

**Plausible** is lighter-weight and privacy-focused but lacks the funnel depth
and session replay.

## 4. Competitor Analysis

Ranked by install experience quality:

1. **Discourse — the benchmark.** Single interactive script
   (`discourse-setup`) asks 3–5 questions, generates config, builds container,
   starts it. First web visit is a setup wizard. Docker only: they refuse to
   support bare-metal. The Launcher was rewritten from bash to Go to eliminate
   runtime dependencies.
2. **Coolify — one-command deploy.** One `curl | bash`, everything
   auto-detected and auto-configured. Secrets auto-generated. Immediate web
   UI.
3. **Plane — sophisticated CLI.** `prime-cli` with Express/Advanced modes.
   Built-in healthcheck, repair, and monitor commands. The most sophisticated
   doctor pattern.
4. **Sentry — best preflight.** Best preflight checks (Docker version, RAM,
   CPU, SSE 4.2 instruction set). `./install.sh` is re-runnable and
   idempotent: it's the tool for both initial setup AND config changes.
5. **GitLab Omnibus — single management verb.** `gitlab-ctl reconfigure` as
   the single management verb. One config file (`gitlab.rb`).
   `gitlab-ctl status`/`check-config`/`tail` for diagnostics.

### Feature comparison matrix

Capabilities rated: **Strong** (market-leading, deep, well-executed),
**Adequate** (functional, gets the job done), **Weak** (exists but limited),
**Absent** (not available).

| Capability             | Discourse | Coolify  | Plane    | Sentry   | GitLab   |
| ---------------------- | --------- | -------- | -------- | -------- | -------- |
| Preflight checks       | Absent    | Weak     | Adequate | Strong   | Adequate |
| Interactive setup      | Strong    | Adequate | Strong   | Weak     | Weak     |
| Doctor / repair        | Weak      | Absent   | Strong   | Absent   | Strong   |
| Re-runnable install    | Adequate  | Adequate | Adequate | Strong   | Strong   |
| Auto-gen secrets       | Strong    | Strong   | Adequate | Adequate | Adequate |
| Progressive disclosure | Adequate  | Strong   | Strong   | Weak     | Weak     |
| Web first-run wizard   | Strong    | Strong   | Adequate | Weak     | Adequate |
| Single config surface  | Strong    | Strong   | Adequate | Adequate | Strong   |
| Support bundle         | Absent    | Absent   | Absent   | Absent   | Adequate |
| CI-tested install      | Weak      | Adequate | Adequate | Strong   | Strong   |

## 5. Pattern Analysis

Ten patterns observed across exemplary projects, with strategic relevance to
OTS:

| Pattern                 | Example                                                                              | Relevance to OTS                                                     |
| ----------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Preflight checks        | Sentry validates Docker version, RAM, CPU, instruction sets before touching anything | `install.sh` could check Valkey, Ruby, Node, overmind upfront        |
| Interactive setup       | Discourse asks hostname + email + SMTP, generates everything else                    | Could reduce `.env` editing to a few prompts                         |
| Doctor command          | Plane `prime-cli repair`, GitLab `gitlab-ctl check-config`, `brew doctor`            | Already started in `cmd_doctor`. Can expand.                         |
| Re-runnable install     | Sentry's `./install.sh` is the recommended way to apply changes                      | OTS `install.sh` already has auto/init/reconcile. Close.             |
| Auto-generated secrets  | Coolify, Discourse generate all crypto material during install                       | OTS already does this via `rake ots:secrets`                         |
| Progressive disclosure  | Plane Express vs Advanced; Discourse skip-SMTP                                       | Simple mode first, full mode details later                           |
| Web first-run wizard    | PostHog gates `/instance/settings` behind onboarding completion                      | Different from CLI-only setup. A web wizard after first boot.        |
| Single config surface   | GitLab one file; Plausible 3 env vars                                                | OTS has `.env` + `config.yaml` + `auth.yaml`. Room to consolidate.   |
| Support bundle          | Mattermost `mmctl system supportpacket`. Sanitized diagnostic archive.               | `install.sh doctor` could output a shareable diagnostic              |
| Opinionated single path | Discourse: Docker only, period                                                       | OTS supports Docker + bare-metal. More surface but more flexibility. |

## 6. Configuration Architecture: File Config vs Web Wizard

### The universal two-tier model

Every project studied separates config the same way:

| Tier      | What goes here                                    | Storage        | Mutability       |
| --------- | ------------------------------------------------- | -------------- | ---------------- |
| Bootstrap | DB credentials, secret keys, ports, external URLs | File / env var | Requires restart |
| Runtime   | Site name, policies, feature toggles, branding    | Database       | Hot-reloaded     |

The dividing line: if the app needs the value to boot, it's bootstrap config.
If the app needs it to behave correctly after boot, it's runtime config.

OTS currently puts almost everything in `.env` (bootstrap tier). Things like
`SITE_HOST`, `SECRET`, `VALKEY_URL` belong there. But branding, TTL options,
and feature toggles are also in `.env`, and those are runtime config that
could live in Redis/database and be web-editable.

### How projects bridge file config to web wizard

Three distinct patterns emerged:

**Pattern A: "File boots, wizard configures"** (Discourse, PostHog, Nextcloud)

- File config gets the app to a running state with minimal values
- First web visit detects empty database state (no admin user, no site
  settings)
- Web wizard handles everything else: writes to database, never touches files
- After wizard: file is read-only, database holds all runtime config

**Pattern B: "File pins, UI defaults"** (Sentry: the most elegant)

- Both config file and web UI can manage overlapping settings
- If a value exists in the config file, it wins and the web UI field is greyed
  out
- If absent from the file, the web UI can set it freely in the database
- Ops team controls infrastructure via files; app admins control behavior via
  web UI

**Pattern C: "Web writes to files"** (WordPress first-run, Gitea first-run,
Mattermost ongoing)

- The web installer generates config files on disk
- Generally considered an anti-pattern after first run: creates permission
  issues in containers, race conditions, breaks read-only filesystems

### First-run detection

| Approach        | Used by                                                                    | Mechanism                              |
| --------------- | -------------------------------------------------------------------------- | -------------------------------------- |
| File existence  | WordPress                                                                  | Does `wp-config.php` exist?            |
| Flag in config  | Gitea (`INSTALL_LOCK`), Nextcloud (`installed => true`)                    | Boolean sentinel in config file        |
| Database state  | Discourse (no admin user), Mattermost (no users), WordPress (empty tables) | Query for sentinel data                |
| External script | Mastodon, GitLab, Sentry                                                   | CLI handles init; no web wizard at all |

The most robust approach combines two: file/flag check + database state.
WordPress does this: missing file triggers config wizard, present file + empty
DB triggers install wizard.

OTS currently uses a Redis counter (`onetime:install:init_count`), which is
effectively the "database state" pattern. That's legitimate: the issue was
just that it was blocking the install flow, which has now been fixed.

> **Config architecture insight:** The "file pins, UI defaults" pattern
> (Sentry) solves a tension that every self-hosted project faces: ops teams
> want config-as-code they can version control and deploy via automation,
> while app admins want a UI they can use without SSH access. By making file
> values authoritative but optional, both workflows coexist. The file is the
> override, the database is the default. OTS already stores runtime state in
> Redis (customer data, metadata counters). Using Redis for runtime config
> settings would be a natural extension of the same infrastructure.

## 7. OTS Current Position

### Existing strengths

- **Re-runnable install**: `install.sh` already has auto/init/reconcile modes.
  Close to the Sentry pattern.
- **Auto-generated secrets**: OTS already does this via `rake ots:secrets`.
  Matches Coolify and Discourse.
- **Doctor command**: Already started in `cmd_doctor`. Foundation exists for
  expansion.
- **Dual deployment paths**: Docker + bare-metal support. More surface but
  more flexibility than Docker-only projects.

### Identified gaps

- **Preflight checks**: `install.sh` could check Valkey, Ruby, Node, overmind
  upfront (Sentry pattern)
- **Interactive setup**: could reduce `.env` editing to a few prompts
  (Discourse pattern)
- **Config surface**: OTS has `.env` + `config.yaml` + `auth.yaml`. Room to
  consolidate (GitLab pattern: one file; Plausible: 3 env vars)
- **Support bundle**: `install.sh doctor` could output a shareable diagnostic
  (Mattermost pattern)
- **Web first-run wizard**: different from CLI-only setup. A web wizard after
  first boot (PostHog pattern)
- **CI-tested install**: no equivalent of Sentry's twice-daily scheduled runs
  from scratch

### What this means for OTS

OTS is closest to the Mastodon/GitLab model: CLI-driven initialization,
file-based config, no web wizard. That's a valid choice. The question is
whether to stay there or evolve toward Sentry's "file pins, UI defaults"
pattern.

The current config hierarchy: Environment variables (`.env`), then YAML config
(`etc/config.yaml`, `etc/auth.yaml`), then Application defaults.

If OTS wanted to add a web-based admin settings layer, the Sentry pattern is
the cleanest path: `.env` values remain authoritative for bootstrap config;
runtime settings (branding, TTL defaults, feature toggles) could have
database-backed defaults; if a value is set in `.env`, it pins and the admin
UI shows it read-only; if not in `.env`, the admin UI can set it in Redis.

This is additive. It doesn't require changing how `.env` or YAML config works
today. It layers database-backed runtime config underneath.

## 8. Strategic Landscape

### Opportunities

- **Progressive disclosure mode**: Simple mode first, full mode details later
  (Plane Express vs Advanced pattern)
- **Consolidate config surface**: Three config files (`.env` + `config.yaml` +
  `auth.yaml`) is higher friction than the single-file patterns from GitLab
  and Plausible
- **Support bundle for diagnostics**: `install.sh doctor` could output a
  sanitized, shareable diagnostic archive (Mattermost pattern). Reduces
  support back-and-forth.
- **Step drop-off instrumentation**: Numbered stages with exit codes to
  identify where users abandon the install

### Threats

- **Rising baseline expectations**: Coolify's one-command deploy and
  Discourse's 3-question setup are resetting what users expect from
  self-hosted install experiences
- **Docker-only convergence**: Discourse refuses bare-metal support entirely;
  maintaining dual paths (Docker + bare-metal) doubles the testing and
  documentation surface
- **CLI tooling arms race**: Plane's `prime-cli` with Express/Advanced modes,
  built-in healthcheck, repair, and monitor sets a new standard for
  self-hosted management CLIs
- **CI testing gap**: Sentry runs `install.sh` from scratch twice daily;
  GitLab runs full E2E nightly. Without equivalent coverage, install
  regressions ship undetected.

## 9. Measurement & Feedback

- **Scarf** for download/install analytics without PII (container registry
  proxy, respects `DO_NOT_TRACK`)
- **Opt-out telemetry** following Homebrew's model: first-run disclosure,
  `DO_NOT_TRACK` env var, collect only OS/arch/version/success-failure
- **Step drop-off rate**: instrument each install step with numbered stages
  and exit codes to identify where users abandon
- **Documentation feedback widgets**: inline "Was this helpful?" on install
  docs, weekly review cycle

## 10. How Tools Compose

The architecture is: BATS + ShellCheck validate the install scripts in CI.
Goss (or Testinfra) validates the resulting system state post-install. Docker
matrix builds test across OS/arch combinations. Vale enforces install doc
quality. PostHog instruments the actual user-facing onboarding flow to measure
TTFV and identify drop-off points. The CI layer catches regressions; the
analytics layer measures whether changes actually improve the experience.

Gap observed: there's less tooling specifically for testing the interactive
parts of install onboarding (wizard flows, first-run configuration UIs). That
space is mostly covered by generic E2E testing tools (Playwright, Cypress)
rather than anything purpose-built.

> **Key insight:** The projects with the best install experiences share a
> philosophy: the install script is a product, not a utility. Discourse
> rewrote their launcher in Go. Sentry runs their `install.sh` in CI twice
> daily. Plane built a dedicated CLI with repair/healthcheck/monitor. The
> common thread isn't a specific tool: it's treating onboarding friction as a
> first-class bug. The lowest-cost, highest-impact moves for OTS are probably:
> (1) ShellCheck in CI, (2) BATS tests for `install.sh` functions, and (3) a
> scheduled GitHub Action that runs `install.sh` in a fresh container and
> validates the result with a few HTTP smoke tests.

---

_Research compiled March 2026. Sources include project documentation, CI
configurations, and DX research from DORA/SPACE frameworks._

## Related

- [install-onboarding-problem-space.md](./install-onboarding-problem-space.md) —
  the OTS-specific problem-space assessment and phased recommendations built
  on this research
