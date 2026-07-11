# Contributing to Onetime Secret

Thanks for helping improve Onetime Secret. This guide gets you from a fresh
clone to a running app and a green test suite with one command, and explains
what we look for in a pull request.

## The 5-minute path

Prerequisites: Ruby (exact version in [`.ruby-version`](.ruby-version)),
Node.js (major version in [`.node-version`](.node-version)),
[pnpm](https://pnpm.io/installation), and
[Valkey](https://valkey.io/download/) or Redis. Recommended but optional:
[direnv](https://direnv.net/) (auto-loads the environment per checkout) and
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

Signup emails are not sent in a default dev environment, so create your
first account from the CLI:

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
bin/setup --test           # test lane: throwaway datastore on :2121
pnpm run test:rspec:fast   # RSpec fast suite
pnpm test                  # Vitest (frontend)
bundle exec try            # Tryouts (Ruby behavior tests)
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
  a CI drift guard (`scripts/test-install/check-docs-commands.sh`) fails
  when docs reference commands that don't exist.

## Where to ask

- Bugs and feature requests: [GitHub issues](https://github.com/onetimesecret/onetimesecret/issues)
- Questions about usage or self-hosting: [docs.onetimesecret.com](https://docs.onetimesecret.com) first, then an issue
- Security vulnerabilities: **not** in a public issue — see [SECURITY.md](SECURITY.md)
- Support options: [SUPPORT.md](SUPPORT.md)
