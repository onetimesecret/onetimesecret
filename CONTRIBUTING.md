# Contributing to Onetime Secret

Thanks for helping improve Onetime Secret. This guide gets you from a fresh
clone to a running app and a green test suite and explains what we look for
in a pull request.

## The 5-minute path

Prerequisites: Ruby (exact version in [`.ruby-version`](.ruby-version)),
Node.js (major version in [`.node-version`](.node-version)),
[pnpm](https://pnpm.io/installation),
[Valkey](https://valkey.io/download/) or Redis, and bash 5+ for the test
lane runner (macOS ships 3.2 — `brew install bash`). Recommended but
optional: [direnv](https://direnv.net/) (auto-loads the environment per
checkout) and
[overmind](https://github.com/DarthSim/overmind) (runs all dev processes).

```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
bin/setup      # deps, config, secrets, generated artifacts, git hooks
bin/dev        # backend + frontend + worker (needs overmind)
```

Then open <http://localhost:3000>. `bin/setup` is idempotent — re-run it any
time (after a pull, when something feels off) and it converges the checkout.
It prints exactly what it did and what to do next.

Prefer zero local installs? Open the repo in GitHub Codespaces (or any
devcontainer runtime) — [`.devcontainer/`](.devcontainer/) runs `bin/setup`
automatically on create, with a Valkey sidecar already wired up. Same path,
prebuilt environment. It's optional; the checkout above is never required to
go through it.

Signup through the web form requires email verification, and a default dev
environment has no SMTP — so seed your first account from the CLI instead
(CLI-provisioned accounts are pre-verified):

```bash
bundle exec rake dev:seed   # dev account + sample secrets, prints credentials
```

By default that's `dev@example.com` / `devpassword` with a couple of sample
secrets on the dashboard (override with `EMAIL=`/`PASSWORD=`). For an
API token instead:

```bash
bin/ots apitoken me@example.com --create   # account + curl-ready API token
```

More on accounts and API credentials: [docs/development/test-accounts.md](docs/development/test-accounts.md).

## Which docs are for you?

- **Contributing to the codebase** (you, here): this file, then
  [docs/development/](docs/development/) for the deeper guides.
- **Self-hosting an instance**: the
  [Self-Hosting Guide](https://docs.onetimesecret.com/en/self-hosting/) —
  don't follow this file for production setups.
- **Running with Docker/Compose**: [docker/README.md](docker/README.md).

## Run what CI runs

CI's fresh-clone job runs `bin/setup` and these same commands from zero on a
clean runner — if they work there, they work here:

```bash
bin/setup --test           # test lane: throwaway datastore on :2163
tests/lanes/run unit       # Ruby: unit tryouts + RSpec fast suite
pnpm test                  # Vitest (frontend)
```

`bin/setup --test` switches the checkout into test mode (a `.test-mode`
marker; with direnv, every shell in the checkout then runs `RACK_ENV=test`).
Plain `bin/setup` switches back to dev mode. `bin/setup --doctor` checks the
environment when something misbehaves.

The full lane matrix (integration suites, PostgreSQL, billing) lives in
[tests/lanes/](tests/lanes/) and `.github/workflows/ci.yml`.

## Generated artifacts — never hand-edit

`generated/locales/` and `generated/schemas/` are build outputs
(`pnpm run locales:sync` and `pnpm run schemas:json:generate`; `bin/setup`
runs both). The sources are `locales/` and the Zod definitions in
`src/schemas/`. Edit the sources; regenerate; never edit the outputs.

## Pull requests

- Target the `main` branch. Keep PRs focused — one concern per PR.
- `bin/setup` installs the pre-commit/pre-push hooks; let them run. They
  handle formatting, linting, and commit-message conventions.
- Add or update tests for behavior you change; the suites above should be
  green before you open the PR.
- If you change a documented setup command, update the docs in the same PR —
  a CI drift guard (`scripts/install-tests/check-docs-commands.sh`) fails
  when docs reference commands that don't exist.

### Committing with unstaged work

Partial staging is supported; concurrent writes during hooks are not safe.
Before committing, pause other writers in the same Git worktree (agents,
autosave, formatters, and generators) and wait for in-flight edits to finish.
Keep them paused until the entire commit command returns, including its
message and post-commit hooks. Use separate Git worktrees for agents that
need to edit and commit independently; assigning different files in one
worktree is not sufficient isolation.

The [upstream pre-commit documentation](https://pre-commit.com/#pre-commit)
explains: “pre-commit only runs on the staged contents of files by temporarily
stashing the unstaged changes while running hooks.” This covers unstaged
tracked changes across the worktree, not just files selected for linting.
The saved changes are a patch at the path printed by pre-commit, not an entry
in `git stash list`; ordinary untracked files are not included.

- **After auto-fixes:** review the diff and selectively re-stage the intended
  changes before retrying. Do not blindly stage unrelated work.
- **If restoration fails:** stop other writers, preserve the printed patch
  file and the current worktree contents, and inspect the diff before trying
  recovery. The patch contains the original snapshot, not necessarily writes
  made during hooks; do not assume it can recover those later edits. The
  [upstream restore implementation](https://github.com/pre-commit/pre-commit/blob/main/pre_commit/staged_files_only.py)
  retries a conflicting patch after checking out indexed contents again,
  which can overwrite concurrent edits.
- **Do not bypass hooks to coordinate writers:** `SKIP=...` skips individual
  hooks, not framework stashing. `git commit --no-verify` does not suppress
  our `prepare-commit-msg` or `post-commit` hooks. Keep the worktree quiet
  instead.

## Where to ask

- Bugs and feature requests: [GitHub issues](https://github.com/onetimesecret/onetimesecret/issues)
- Questions about usage or self-hosting: [docs.onetimesecret.com](https://docs.onetimesecret.com) first, then an issue
- Security vulnerabilities: **not** in a public issue — see [SECURITY.md](SECURITY.md)
- Support options: [SUPPORT.md](SUPPORT.md)
