---
title: Install Onboarding — Front-Door Assessment
type: assessment
status: draft
updated: 2026-07-09
---

Assessment of the repo's onboarding surface — install scripts, the rake
init task, docs, and Docker setup — against what the best self-hosted
projects do.

## TL;DR

Your individual pieces are unusually good — `install.sh doctor`, idempotent
everything, the derived-secrets model, Valkey/Redis fallback, the `.envrc`
lane switching. The problem is that they're organized by *mode*
(`install.sh` / `install-dev.sh` / `install-test.sh`) rather than by
*persona*, the golden paths in the README are broken or contradictory, and
the version-of-truth for toolchain requirements is scattered across six
files that disagree with each other. The best comparable projects win on
exactly the things you're missing: one zero-prerequisite path for
self-hosters (`docker compose up` that actually works), one canonical
command for contributors (`bin/setup` on a clean fork, no maintainer config
required), and a single pinned source of truth for tool versions.

## Where you're going wrong — concrete findings

**1. The README's Docker Compose quick start is broken.** Root
`README.md:133` says `cp .env.example .env && docker compose up`. But
`.env.example` ships `SECRET=` empty, and `docker-compose.simple.yml:27`
has `SECRET=${SECRET:?SECRET must be set — run ./install.sh}`. So the
documented path fails immediately — and the error message tells a Docker
user (who chose Docker to avoid the Ruby toolchain) to run a script that
requires Ruby, Bundler, and Node. `docker/README.md` has the missing step
(`echo "SECRET=$(openssl rand -hex 32)" >> .env`), but the front-page
README doesn't. This is the highest-traffic funnel and it 404s at step two.

**2. `install.sh` pins Ruby against a file that doesn't exist.**
`install.sh:179` checks `.ruby-version` — there is no `.ruby-version` in
the repo. Every user who runs `./install.sh init` gets "version not
verified" warnings on the happy path. Meanwhile `ci.yml` watches
`.ruby-version` and `.node-version` as change-trigger paths (also
nonexistent) and hardcodes Ruby 3.4.9. The stated Ruby floor is different
in five places: Gemfile (`>= 3.3.6`), `install-test.sh` (3.4.7), README
("Ruby 3.4+"), CI (3.4.9), install.sh (undefined). Node is worse: `.nvmrc`
says 25, CI workflows variously use 20, 22, and 25. Nobody can answer "what
versions do I need?" from the repo, including its own scripts. Also,
`check_version` requires *exact* equality with `.ruby-version` — even once
the file exists, a user on 3.4.8 vs a pinned 3.4.9 gets a hard `die`, which
is harsher than the Gemfile itself.

**3. `install-dev.sh` is a maintainer tool wearing the contributor script's
name.** Its primary behavior is symlinking config from `$OTS_DEV_CONFIG`
(`~/.config/onetimesecret-dev`) — a directory only the maintainer has — and
pointing a Caddy webroot symlink at `/var/www/public/web` — a path only the
maintainer's machines have. A fresh forker running it hits: a Bash 4+ hard
fail on stock macOS, a hard requirement on direnv, warnings for missing
overmind and pre-commit, "Warning: ~/.config/onetimesecret-dev does not
exist — config symlinks will be skipped", and "Skip: /var/www/public does
not exist." The fallback copies (`.env.example` → `.env`, etc.) do
eventually produce a working state, but the contributor's first-run
experience is a wall of warnings about the maintainer's environment, and —
critically — it never generates secrets, so `.env` has `SECRET=` empty and
the app won't boot correctly until they separately discover
`install.sh init`. The happy path for outsiders is the fallback path.

**4. Three scripts that overlap and drift.** The `.envrc` heredoc is
duplicated verbatim in `install-dev.sh` and `install-test.sh` (they will
diverge). Config seeding is implemented three different ways: `install.sh`
copies three named defaults, `install-test.sh` globs all of
`etc/defaults/*`, `install-dev.sh` symlinks from shared config. `install.sh`
reimplements `.env` parsing, Redis URL resolution, and auth-mode detection
in sed/bash — logic the app already owns. And nothing tells a new arrival
*which script is for them*: the names describe lanes, not audiences.

**5. Trust-eroding staleness in the front door.** `.env.example`'s header
says "Source environment: source .env.sh" — a mechanism `install-dev.sh`
itself says was replaced by `.envrc`. `README.md:151` says "This version of
**Familia** was developed with…" — a copy-paste from another project,
sitting on the repo's landing page. Small things, but a prospective
self-hoster is pattern-matching for "is this project maintained carefully?"
and these are the first files they read.

**6. Missing table stakes for OSS onboarding.** No `CONTRIBUTING.md`
(GitHub surfaces this on every PR/issue). No devcontainer/Codespaces
config. No `.tool-versions`/`mise.toml`. No seed data or dev account task —
after setup succeeds, a contributor has an empty app and no test login. And
no first-run verification: `install.sh` ends with `doctor`, which checks
files exist, but never proves the app works (create a secret, retrieve
it). `install-test.sh` actually has the right instinct with its config
smoke test — the pattern just never made it to the other two scripts.

**7. Heavy host-tool constellation with no containerized escape hatch for
dev.** The full dev loop wants: Ruby, Bundler, Node, pnpm, Valkey, direnv,
overmind, pre-commit, Bash 4+, and (full mode) PostgreSQL + RabbitMQ — all
installed on the host. There is `compose.test.yml` and a mailpit compose
file, but no "run the *dependencies* in containers, code on host" profile,
which is how most polyglot projects (Cal.com, Outline, Plausible dev)
neutralize the "install five services locally" problem.

## What successful projects do that's worth borrowing

- **Zero-prerequisite self-hosting**: Plausible, Umami, Vaultwarden,
  Outline — `docker compose up` works with at most one documented
  secret-generation command, and several generate/persist the secret on
  first boot. Gitea goes further with a web-based first-run wizard. The
  equivalent here: make the container entrypoint generate `SECRET` on first
  boot when unset (persisted to the volume, with a loud log line saying
  where it is and to back it up), or add a
  `docker compose run --rm app init` bootstrap. Docker users should never
  be told to run a Ruby script.
- **One canonical contributor command**: the Rails `bin/setup` convention /
  GitHub's "scripts to rule them all." Discourse has `discourse-setup`;
  Mastodon has the interactive `rake mastodon:setup`; Zulip and GitLab
  (GDK) ship dedicated provisioning that gets a fork to a running app in
  one command. The key property: it works on a *clean fork with zero
  pre-existing config* and ends with the app demonstrably running.
- **Pinned toolchain in one file**: `.tool-versions` (asdf/mise/rbenv all
  read it) or `mise.toml`, referenced by CI via
  `ruby-version-file:`/`node-version-file:` so drift is structurally
  impossible.
- **Devcontainer + Codespaces**: Discourse, Cal.com, Nextcloud. For
  drive-by contributors this collapses the entire tool constellation to
  "click Open in Codespaces." Given the dependency list here, this is
  probably the single highest-leverage addition.
- **Seed data**: `rake dev:seed` or equivalent creating a dev admin +
  sample secrets, so the first `bin/dev` shows a populated, log-in-able
  app.

## Recommended plan, prioritized

**P0 — fix what's broken (hours, not days):**

1. Fix the compose quick start: entrypoint-generated `SECRET` on first boot
   (or fix root README + make the compose error message Docker-appropriate).
2. Add `.ruby-version` and `.node-version`; align Gemfile/README/
   install-test/CI to read from them. Relax `check_version` to compare
   sensibly (minor-level, or defer to Bundler).
3. Fix `.env.example`'s stale `source .env.sh` instruction and the
   "Familia" paragraph in the README.

**P1 — reorganize around personas:**

4. Create `bin/setup` as the single contributor entry point (fold in the
   best of `install-test.sh`, which is already the closest-to-ideal
   script): tool checks with actionable messages, deps, seed configs from
   defaults, **generate secrets**, start throwaway Valkey if none running,
   HTTP smoke test, print `bin/dev` next steps. Contributor docs mention
   exactly one command.
5. Move the maintainer symlink-farm and Caddy-webroot logic out of
   `install-dev.sh` into `scripts/` (or behind `--maintainer`), so the
   script a forker finds doesn't warn about the maintainer's machines.
6. Keep `install.sh` as the *self-hoster* bare-metal path only, and say so
   in its header and the README.
7. Add `CONTRIBUTING.md` with the 5-minute path, the persona map (self-host
   Docker / self-host bare-metal / contributor / test), and where to get
   help.
8. Deduplicate: one shared `.envrc` template, one config-seeding
   implementation, and have shell scripts shell out to `bin/ots` for
   env/config resolution instead of re-parsing `.env` with sed.

**P2 — the DX multipliers:**

9. `.devcontainer/` + Codespaces support.
10. A dev-dependencies compose profile (Valkey, Mailpit, Postgres,
    RabbitMQ in containers; code on host) so the only host requirements
    are Ruby, Node, pnpm.
11. `rake dev:seed` with a dev account and sample data, wired into
    `bin/setup`.
12. End every setup path with proof-of-life: boot, create a secret via the
    API, retrieve it, print the URL. `doctor` checks preconditions;
    nothing currently checks the *outcome*.

The unifying principle: the project is optimized for the maintainer's own
workflow (worktree forests, shared config, lane switching — all genuinely
sophisticated), and the outsider paths have decayed into fallback branches
and stale docs. The fix is less about writing new tooling than about
drawing a hard line between maintainer tooling and the two public front
doors, then making each front door a single command that provably works
from nothing.
