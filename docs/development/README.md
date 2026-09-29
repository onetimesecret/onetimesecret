# Development Guide

Deeper reference for developing Onetime Secret. Start with
[CONTRIBUTING.md](../../CONTRIBUTING.md) if you haven't set up a checkout
yet — the short version:

```bash
bin/setup                   # one command: deps, config, secrets, generated artifacts, git hooks
bin/dev                     # backend + frontend + worker (overmind, Procfile.dev)
bundle exec rake dev:seed   # first login: dev account + sample secrets, prints credentials
```

Both are idempotent and safe to re-run. `bin/setup --doctor` checks the
environment; `bin/setup --test` switches to the test lane (see
[Testing](#testing)); `bin/setup --help` lists every lane.

For a zero-install environment, open the repo in GitHub Codespaces or any
devcontainer runtime: [`.devcontainer/`](../../.devcontainer/) is
compose-based (app + Valkey) and runs `bin/setup` on create. The
`devcontainer-ci.yml` workflow rebuilds and smoke-tests it weekly.

## Running the application

`bin/dev` runs everything via [overmind](https://github.com/DarthSim/overmind)
from `Procfile.dev`. The main window is a pure log stream; control individual
processes from a separate terminal:

```bash
overmind connect backend       # Attach for debugger/pry (Ctrl+b,d to detach)
overmind restart frontend      # Restart a single process
overmind stop worker           # Stop a specific process
```

There is also a `--volatile` flag for ephemeral runs with no persistent data:
`bin/dev --volatile`.

For a production-style run (no Vite dev server, pre-built assets served
through Rack):

```bash
pnpm run build
RACK_ENV=production bundle exec puma -C etc/examples/puma.example.rb
```

## Testing

```bash
docker compose -f compose.test.yml up --wait -d  # test services (or: podman compose)
pnpm run build                                  # required before the Ruby unit lane
tests/lanes/run unit                            # Tryouts + RSpec fast suite (see: tests/lanes/run --list)
pnpm test                                       # Vitest (frontend; no services needed)
scripts/tests/run.sh                            # shell tests for the CI scripts (no services needed)
scripts/check-shell-lint.sh                     # shellcheck + actionlint against the recorded baseline
```

Ruby tests run through the lane runner, which scrubs ambient dev env vars
and loads the lane's own environment — the same entrypoint CI uses. It
needs bash 5+ (macOS ships 3.2 — `brew install bash`); a too-old one is
flagged by `bin/setup --doctor`. See [tests/lanes/](../../tests/lanes/)
for the full lane matrix (integration, PostgreSQL-backed auth, billing,
migrations).

`bin/setup --test` puts the checkout in test mode: with direnv installed,
every shell in the checkout loads `.env.test` and runs `RACK_ENV=test` until
you switch back with plain `bin/setup`. It also mirrors CI's dependency
contract — `pnpm install --frozen-lockfile` on every run, plus the Playwright
browsers (chromium, firefox, webkit) that `tests/browser/` drives through
`@playwright/test`. Set `OTS_SETUP_SKIP_BROWSERS=1` to skip the browser
download; on Linux the browsers may additionally need OS packages
(`pnpm exec playwright install-deps`, which setup never runs for you).
`bin/setup --doctor` reports whether the browser binaries are present.

`scripts/tests/run.sh` covers the shell scripts that CI itself runs — the
Sentry sourcemap delivery reporters in `scripts/ci/`, whose failure mode is
a green check next to a summary that says nothing shipped. They are outside
the lane runner on purpose: no datastore, no Ruby, no network. Each test
scrubs the ambient `SENTRY_*` variables, so a shell configured against the
self-hosted Sentry does not change the result. `scripts/check-shell-lint.sh`
runs shellcheck and actionlint over the repo and fails on anything above the
baseline in `.github/lint-baseline/`; both run in CI as `Static analysis`.

### Choosing Tryouts or RSpec for Ruby model tests

Choose by isolation needs, not by whether the test uses a real datastore:

- Prefer **Tryouts** for a linear scenario over real records when no
  instrumentation is needed and the sequence itself is what the test describes.
- Use **RSpec** when a test needs to instrument a frozen Familia object.
  Stub the class accessor for one example and return a delegator around the
  real object, rather than patching the object's class for the whole process.
- Give independent assertions independent setup. Do not make unrelated cases
  depend on a record left behind by an earlier case.

This is guidance for choosing new tests, not a mandate to convert existing
Tryouts. Model behavior already lives in both frameworks. Datastore-backed
RSpec unit tests are an established pattern; see the
[Organization destroy guard spec](../../spec/unit/onetime/models/organization/destroy_domain_guard_spec.rb).
The `:datastore` tag describes that dependency; `spec/spec_helper.rb` does not
attach setup, cleanup, or isolation behavior to it. Continue to run both
frameworks through the [lane runner](../../tests/lanes/README.md).

#### Instrumenting a frozen Familia index

The [CustomDomain canonical-release spec](../../spec/unit/onetime/models/custom_domain/destroy_canonical_release_spec.rb)
is the reference pattern:

1. Capture the real index **before** stubbing its class accessor.
2. Wrap it in a `SimpleDelegator` that records the operation, arguments,
   transaction state, and real return value while forwarding to the index.
3. Stub the accessor in a per-example `before` hook. RSpec restores it after
   each example; the frozen index and its class remain unchanged.
4. Create fresh records for each example. In `after`, clean up those records
   and any manually written index fields. Handle record-destruction errors
   without skipping the subsequent field cleanup; report cleanup failures.
   Do not flush the shared datastore.

Stubbing the accessor does not replace the datastore operation with a double.
The delegator forwards `release_field` to the real index, so the spec observes
an actual EVAL queued in Familia's MULTI transaction and a real `Redis::Future`.
A canned return value would not establish that transaction behavior.

#### Why the destroy-release test moved to RSpec

Commit `6cfe4886ed` replaced a destroy-release Tryout with a scoped RSpec test
for isolation, not additional behavioral coverage. The Tryout prepended a
recorder module onto `Familia::HashKey` because the index object was frozen.
Tryout files in a batch share a Ruby process, so the prepend remained active
for later files even after teardown disabled recording. If execution stopped
before teardown cleared the recording flag, recording could remain enabled.
The Tryout also carried one record through successive cases, allowing an
initial failure to cascade.

The replacement retained the checks for an A-label (ASCII) claim on creation,
release inside the destroy transaction with the correct field and identifier,
a `Redis::Future` return value, removal of the record and claim, re-registration
after destroy, and preservation of a claim owned by another identifier. The
re-registration check in both versions creates the Unicode spelling again
and inspects its canonical A-label claim; it does not separately register
both spellings. The dropped shared-object identity assertion justified the
old recorder, rather than testing model behavior. The current spec also
checks that destruction removes the domain from its organization.

## Changing stored data

Five different mechanisms change data after the fact: Familia migrations
under `bin/ots migrate`, the `bin/ots migrations` backfill commands,
housekeeping chores, the scheduled audit/repair jobs, and the Sequel
auth-database migrations. [data-migrations.md](./data-migrations.md) says
which to use when, where each lives, and which legacy tolerances in the
models are waiting on one of them.

## Debugging

To enable debug logging, set the `ONETIME_DEBUG` environment variable to
`true`, `1`, or `yes` for more verbose output:

```bash
ONETIME_DEBUG=true bin/dev
```

For interactive debugging, add `binding.pry` (or `debugger`) and attach to
the process with `overmind connect backend`.

## Frontend development

Development mode (Vite dev server + HMR) enables itself when
`RACK_ENV=development` — the default config reads:

```yaml
development:
  enabled: <%= ['development', 'dev'].include?(ENV['RACK_ENV']) %>
```

To pin it explicitly in `etc/config.yaml`, use string keys (the config
loader ignores symbol-keyed YAML):

```yaml
development:
  enabled: true
  frontend_host: 'http://localhost:5173'
```

### Vite development server security

For security, the Vite development server only allows connections from
`localhost` by default. If you need to access the dev server from another
machine on your network (e.g., a VM or a mobile device), you must explicitly
configure `vite.config.ts` to allow your host:

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  // ... other config
  server: {
    host: '0.0.0.0', // Listen on all network interfaces
    hmr: {
      host: 'your-local-ip-address', // Your machine's IP on the local network
    },
  },
});
```

> **Security Warning:** Never set `server.hmr.host` to a public IP or expose
> the Vite dev server to the internet, as this can create security
> vulnerabilities.

## Redis/Valkey

The application supports both Redis and Valkey servers (they are
wire-compatible). `bin/setup` auto-discovers whichever is installed; to
override, set the same two variables the `package.json` scripts read:

```bash
export VALKEY_SERVER=valkey-server  # or redis-server
export VALKEY_CLI=valkey-cli        # or redis-cli
```

Dev datastore helpers (default port):

```bash
pnpm run database:start     # Start server in daemon mode
pnpm run database:start:fg  # Start server in foreground
pnpm run database:stop      # Stop server
pnpm run database:status    # Check if server is running
```

Test datastore helpers (port 2163, no persistence — started by
`bin/setup --test`):

```bash
pnpm run test:database:start
pnpm run test:database:stop
pnpm run test:database:status
pnpm run test:database:clean   # Flush the test databases (asks first)
```

## Git hooks and merge drivers

`bin/setup` installs the [pre-commit](https://pre-commit.com)-managed hooks
(pre-commit, prepare-commit-msg, post-commit, post-checkout, post-merge,
pre-push) when `pre-commit` is on your PATH.

### New worktrees (opt-in)

A new worktree has no dependencies, config or generated files. To have
`git worktree add` run `bin/setup` in it, opt in once per clone:

```bash
git config ots.worktreeSetup true
```

The post-checkout hook ([`tools/setup/new-worktree.sh`](../../tools/setup/new-worktree.sh))
then runs `bin/setup --dev` when the worktree's name starts with `dev`, and
`bin/setup --test` otherwise. The name is the worktree's directory, or its
parent directory for a nested worktree: one whose directory is named after
the main checkout or after its own grandparent
(`worktrees/onetimesecret/dev-api/onetimesecret` is `dev-api`).

- Output goes to `tmp/worktree-setup.log` in the new worktree. A failed
  setup does not fail `git worktree add`; check the log.
- It applies to anything that runs `git worktree add`, including Zed. Tools
  that create worktrees without running git hooks are not covered; run
  `bin/setup` there yourself.
- The worktree's own commit must include this hook, so worktrees of older
  branches are not set up.
- The hook and `bin/setup` are the new worktree's own files, so setup runs
  whatever code the checked-out branch ships, the same as `bundle install`
  or `pnpm install` would. Do not opt in a clone you use to check out
  branches you have not read, and skip the hook for such a checkout as
  below. Only the clone's own config opts in; a global setting is ignored.
- To skip it once: `git -c core.hooksPath=/dev/null worktree add ...` (this
  skips every hook). To opt out: `git config --unset ots.worktreeSetup`.

### Git JSON merge driver (recommended)

This repository uses a custom merge driver for locale JSON files to
automatically resolve conflicts:

1. Install dependencies: `pnpm install`
2. Configure Git (one-time setup):
   ```bash
   git config merge.json.driver "npx git-json-merge %A %O %B"
   git config merge.json.name "Custom 3-way merge driver for JSON files"
   ```

The driver automatically resolves conflicts when multiple branches modify
different keys in the same locale file. If a conflict cannot be resolved
automatically (e.g., same key modified on both sides), Git falls back to
standard conflict markers.

## Docker-related tips

### Container name already in use

If you encounter an error like `docker: Error response from daemon: Conflict.
The container name "/onetimesecret" is already in use`, a container with that
name already exists. Remove the old container or start a new one with a
different name:

```bash
# To remove the existing container
docker rm onetimesecret

# To start a new container with a different name
docker run --name onetimesecret-new ...
```

### Optimizing Docker builds

To inspect the layers of a Docker image and identify opportunities for
optimization, use the `docker history` command:

```bash
docker history onetimesecret --format "table {{.CreatedBy}}\t{{.Size}}"

# Or use dive for a more detailed analysis:
# brew install dive
# dive onetimesecret
```

### Docker Compose

Docker Compose configurations are included in this repository. The root
`docker-compose.yml` includes a simple profile (app + Valkey) by default,
with a full production stack (Caddy, RabbitMQ, workers) available:

```bash
[ -f .env ] || cp -p .env.example .env
docker compose up
```

See `docker-compose.yml` for profile options and
[docker/README.md](../../docker/README.md) for complete setup documentation.
