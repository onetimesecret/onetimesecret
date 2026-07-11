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
bin/setup --test               # throwaway datastore on :2121, .test-mode marker
pnpm run test:rspec:fast       # RSpec fast suite
pnpm test                      # Vitest (frontend)
bundle exec try                # Tryouts (Ruby behavior tests)
```

`bin/setup --test` puts the checkout in test mode: with direnv installed,
every shell in the checkout loads `.env.test` and runs `RACK_ENV=test` until
you switch back with plain `bin/setup`. Without direnv the suites still work —
`spec_helper` forces `RACK_ENV=test` itself.

The integration suites (PostgreSQL-backed auth, billing) need extra services;
see [tests/lanes/](../../tests/lanes/) for the lane matrix CI runs.

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

Test datastore helpers (port 2121, no persistence — started by
`bin/setup --test`):

```bash
pnpm run test:database:start
pnpm run test:database:stop
pnpm run test:database:status
pnpm run test:database:clean   # Flush the test databases (asks first)
```

## Git hooks and merge drivers

`bin/setup` installs the [pre-commit](https://pre-commit.com)-managed hooks
(pre-commit, prepare-commit-msg, pre-push) when `pre-commit` is on your PATH.

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
