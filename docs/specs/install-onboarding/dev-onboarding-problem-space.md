---
title: Developer Onboarding — Problem Space and Recommendations
type: assessment
status: draft
updated: 2026-07-09
---

# Developer Onboarding: Problem Space and Recommendations

The contributor-persona companion to
[install-onboarding-problem-space.md](./install-onboarding-problem-space.md),
which covers operators (self-hosters). That doc's P1–P3 and R-series do not
touch the person this doc is about: **someone who forks the repo and wants to
run the app, make a change, and open a PR** — with no
`~/.config/onetimesecret-dev`, no `/var/www`, no direnv/overmind, stock macOS
bash 3.2 or a fresh Linux box.

Recommendation IDs are D-series (D1–D8), referenceable in follow-up issues
alongside the operator R-series. Ground truth for every claim here:
[install-onboarding-current-state.md](./install-onboarding-current-state.md)
(file:line evidence + empirical first-run transcripts from a clean container,
July 2026).

---

## 1. The Problem Space

### The structural root: two personas, one script namespace

The dev tooling is written for the **maintainer's** environment and the
**contributor** gets the fallback branches. Concretely:

- `install-dev.sh`'s primary behavior is symlinking config from
  `$OTS_DEV_CONFIG` (a directory only maintainer machines have) and pointing a
  Caddy webroot at `/var/www/public/web` (a path only maintainer machines
  have). A contributor running it gets a wall of warnings about an
  environment that isn't theirs — when it runs at all.
- Hard gates exceed actual requirements: `install-dev.sh` **dies** without
  direnv; `bin/dev` and even `bin/backend` (documented as the
  no-overmind "Option B") **die** without overmind; `install.sh` **dies** on
  Node 22 — a version the frontend demonstrably builds on in 21s and that
  most CI jobs themselves use.
- The dev path never generates secrets: `install-dev.sh` copies `.env.example`
  → `.env` and stops, leaving `SECRET=` empty. Booting requires knowing to
  also run `./install.sh init` (which has its own gates) or
  `rake ots:secrets` (undocumented).
- Nothing tells a newcomer which of the three `install-*.sh` scripts is
  theirs. The names describe lanes (dev/test/plain), not audiences, and the
  docs disagree about the sequence.

None of this is visible from a maintainer machine, where the shared config
dir exists, direnv/overmind are installed, the locale is UTF-8, and the right
Ruby is already active. This is the "poisoned well" problem —
[install-onboarding-testing-strategy.md](./install-onboarding-testing-strategy.md)
is the systematic answer; this doc fixes what the clean rooms revealed.

### What the clean-slate runs proved (July 2026, fresh Linux container)

The empirical bottom line: **zero of the three documented entry points
complete on a clean machine**, yet the machinery underneath is genuinely
sound. On the same box, once the gates were bypassed by hand:
`install-test.sh` went green in **76 seconds**; the RSpec fast lane passed
**260/260 in 2.6s**; `pnpm run build` on "too-old" Node 22 produced a fully
working UI in **21 seconds**; the booted app answered
`{"success":true,"status":"nominal"}`. The product is minutes away from a
15-minute TTFHW — the doors are just locked from the inside. Full transcripts
and the failure cascade (Node gate → false Gemfile floor → UTF-8 locale crash
→ assetless UI) are in the
[current-state audit](./install-onboarding-current-state.md).

### What the best projects do (verified July 2026)

- **One canonical idempotent command** owns the contributor path: Rails
  `bin/setup` ("idempotent, so that you can run it at any time and get an
  expectable outcome"), Mastodon `bin/setup`, Zulip `tools/provision`, GDK
  `gdk install`. The GitHub scripts-to-rule-them-all convention
  (`script/bootstrap|setup|update|test|cibuild`) is the formalization; its
  living insight is that **CI enters through the same script contributors
  run**, so the path cannot rot untested.
- **The setup command is also the devcontainer's `postCreateCommand`**
  (Mastodon, Home Assistant, Rails, forem) — every Codespace boot is a fresh
  test of it, and contributors who want zero local setup get exactly that.
- **Versions are declared once, read by everything**: `.ruby-version` +
  `.node-version` consumed by rbenv/mise/asdf locally, `ruby/setup-ruby` and
  `actions/setup-node` in CI, `ruby file: ".ruby-version"` in the Gemfile.
  pnpm 11 self-enforces `packageManager`/`engines`.
- **Optional tools enhance, never gate.** Zulip's provision doesn't require a
  process manager to exist before it will install dependencies.
- **CONTRIBUTING.md is table stakes** — GitHub surfaces it on every issue/PR;
  ours is absent (no code of conduct, no SUPPORT.md either).

## 2. What Already Exists (don't rebuild)

| Asset | Why it matters |
| --- | --- |
| `install-test.sh` | Empirically survives a clean fork end-to-end (76s). Graceful direnv skip, Valkey→Redis fallback, config seeding, throwaway datastore, config smoke test. **This is the embryo of `bin/setup`.** |
| `install.sh doctor` | Right instinct, right shape; extend per testing-strategy Tier 4 (read pins, probe services) rather than replace. |
| `.envrc` lane switching (dev/test via `.test-mode`) | Genuinely good for direnv users; keep as the enhanced path. |
| `rake ots:secrets` | Idempotent, well-structured secret generation with derivation — just unreachable from the dev path today. |
| `bin/dev` port/procfile handling, `--volatile` mode | Good DX for those past the gates. |
| `docs/development/` breadth (i18n, redis-debug, test-accounts, isolated-envs) | Depth exists; the front door is what's missing. |
| Extensive pnpm script catalog | Powerful but undiscoverable; a front-door doc fixes that, not new scripts. |

## 3. Recommendations (D-series)

Ordered so each unblocks the next; D1–D3 are the substance, D4–D8 the
compounding layers.

### D1 — Contributor-first defaults in the existing scripts

**D1.1 Gates become fallbacks.** `install-dev.sh` proceeds without direnv
(generate `.envrc` anyway for later, print how the no-direnv flow works);
`bin/dev` falls back when overmind is absent (run foreman if present, else
print the two commands to run in two terminals); `bin/backend` must not
require overmind at all (it defeats its documented purpose as the
separate-terminals option). Missing-tool messages say what the tool *adds*,
not just its install URL.

**D1.2 The dev path produces a bootable app.** `install-dev.sh` (or D2's
`bin/setup`) runs `rake ots:secrets` when `SECRET` is empty — the single
biggest silent dead-end on the contributor path today.

**D1.3 Maintainer tooling moves out of the front door.** The
`$OTS_DEV_CONFIG` symlink farm and Caddy-webroot logic relocate to
`scripts/maintainer-setup.sh` (or `install-dev.sh --maintainer`). Default
output on a clean fork: zero warnings about machines the contributor doesn't
own.

**D1.4 Version gates match reality.** Node gate aligned with what the build
actually needs (Node 22 LTS works today — empirically); Ruby check compares
against `.ruby-version` (D4) with a clear "how to fix" message, not exact-match
`die`. Gates that block versions CI itself uses are bugs by definition.

### D2 — One canonical entry point: `bin/setup`

The Rails-convention name, built on the `install-test.sh` spine (it already
works): tool checks with actionable messages → deps (`bundle`, `pnpm`) →
config seeding from `etc/defaults/` → **secrets generation** → generated
artifacts (locales, schemas) → start/verify a datastore → proof-of-life
(create+read a secret via the API, per testing-strategy §4) → print next
steps (`bin/dev`, test commands). Idempotent; safe to re-run forever;
`bin/setup --test` selects the test lane (absorbing `install-test.sh`'s
marker behavior). The three `install-*.sh` scripts become thin delegates or
aliases during a deprecation window — README and CONTRIBUTING mention exactly
one command. CI's fresh-clone job (testing-strategy §3.2c) runs this same
script, which is what keeps it honest permanently.

### D3 — `CONTRIBUTING.md` + community health files

Sections: the 5-minute path (`bin/setup` → `bin/dev` → URL), the persona map
(contributor vs self-hoster docs), how to run what CI runs, where generated
artifacts come from, PR expectations, where to ask questions. Plus
`SUPPORT.md` and a code of conduct. Link prominently from README. Keep
commands thin so the docs-drift grep (testing-strategy §3.2c) can guard them.

### D4 — Version truth: pin files as the single source

Add `.ruby-version` and `.node-version` (both already *referenced* by
`install.sh` and `ci.yml` — the files just don't exist); Gemfile becomes
`ruby file: ".ruby-version"` (retiring the empirically-false `>= 3.3.6`
floor); CI switches to `ruby-version-file`/`node-version-file`; a CI grep
asserts the Dockerfile matches. `.nvmrc` either becomes `.node-version`'s
symlink-equivalent or is retired to avoid a second Node declaration.
(Details and citations: testing-strategy §6.)

### D5 — Devcontainer + Codespaces

Compose-based (app + Valkey), `postCreateCommand: bin/setup`, kept honest by
a `devcontainers/ci` workflow with weekly cron (testing-strategy §5).
Depends on D1/D2 — the setup script must survive a clean machine first. This
is both the zero-install contributor path and the maintainer's own on-demand
clean room. Never mandatory.

### D6 — First-session experience: seed data and first login

After `bin/dev`, a contributor needs an account and something to look at.
A `bin/setup`-invoked (or `rake dev:seed`) step that creates a dev account
with a known password and a couple of sample secrets — and prints the
credentials. Document the no-SMTP local signup/verification story (the
existing `docs/development/test-accounts.md` content graduates into the
CONTRIBUTING flow). The empirical boot test reached a working instance and
then had nothing to log in with — that's the last mile of TTFHW.

### D7 — Docs coherence for the dev path

`docs/development/README.md` presents one sequence (D2's), demotes
alternatives to an appendix, and drops claims the code contradicts (Option B
requires overmind today; `bin/console` still sources the retired `.env.sh`;
`.env.example`'s header references `.env.sh` too). The HMR/dev-mode section
gets verified against actual config keys. Every stale reference is
enumerated with file:line in the current-state audit.

### D8 — Drift guards for the dev path

The doctor extensions (read pins, probe Valkey, check ports — testing-strategy
§6) run as `bin/setup`'s first and last step, GDK-style; the fresh-clone CI
job (§3.2c there) with idempotency re-run and litter check is the permanent
regression net; its duration is tracked as the contributor TTFHW proxy.

### What NOT to do

- **ND1 — Don't require the maintainer stack of anyone.** direnv, overmind,
  pre-commit, worktree forests are excellent *enhancements*; each hard gate
  on them converts a contributor into a bounce.
- **ND2 — Don't add a fourth install script.** D2 consolidates; adding
  `bin/setup` *alongside* three live install scripts long-term recreates the
  which-one-is-mine problem it solves.
- **ND3 — Don't reach for Nix/devenv to fix drift** (testing-strategy §6
  anti-recommendation) — pins + mise + devcontainer capture most of the value
  at a fraction of the cost, with tools contributors already know.
- **ND4 — Don't gate on versions the codebase doesn't require.** Every gate
  needs an empirical justification (CI proves Node 22 builds; the gate says
  25+). Gates exist to save users time, not to enforce aspiration.

## 4. How This Maps to Contributor Complaints

| Complaint shape | Addressed by |
| --- | --- |
| "Which script do I even run?" | D2 (one entry point), D3 (CONTRIBUTING), D7 |
| "Setup died asking for a tool I've never heard of" | D1.1, ND1 |
| "It set up but the app won't boot / blank page" | D1.2 (secrets), D6 (first login), current-state F-series fixes (locale, build step) |
| "Works on my machine but not in CI / vice versa" | D4 (pins), D8 (fresh-clone job) |
| "I don't want to install five tools for a doc fix" | D5 (Codespaces path), ND1 |
| "My Ruby/Node is 'wrong' but the app runs fine" | D1.4, D4 |

## Related

- [install-onboarding-problem-space.md](./install-onboarding-problem-space.md) — operator persona (R-series)
- [install-onboarding-current-state.md](./install-onboarding-current-state.md) — evidence: file:line findings + empirical transcripts
- [install-onboarding-testing-strategy.md](./install-onboarding-testing-strategy.md) — how D-series stays fixed once fixed
- [install-onboarding-work-chunks.md](./install-onboarding-work-chunks.md) — the D/R/F items packaged into shippable chunks
- `docs/development/README.md`, `docs/development/test-accounts.md` — current dev docs this plan reorganizes
