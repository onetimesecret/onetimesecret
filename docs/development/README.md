# Development Guide

This guide provides tips and best practices for developing Onetime Secret.

## Debugging

To enable debug logging, set the `ONETIME_DEBUG` environment variable to `true`, `1`, or `yes`. This will provide more verbose output to help troubleshoot issues.

```bash
export ONETIME_DEBUG=true
bin/backend
```

## Initial Setup

Run `./install.sh init` from the project root to install dependencies, generate secrets, and prepare the `.env` file. Use `./install.sh doctor` to verify your environment.

## Running the Application

There are three ways to run the application locally for development.

### Option A: Overmind (recommended)

[Overmind](https://github.com/DarthSim/overmind) runs backend, frontend, and worker from a single command using `Procfile.dev`:

```bash
brew install overmind          # macOS (one-time)
./install-dev.sh               # Link config files + install gems and packages (one-time per checkout)
bin/dev                        # Start all processes
```

`install-dev.sh` symlinks config files from the directory set by `$OTS_DEV_CONFIG` (default: `~/.config/onetimesecret-dev/`) into the checkout (e.g., `etc/config.yaml`, `etc/puma.rb`, `Procfile.dev`), then runs `bundle install` and `pnpm install`. Run it once per checkout or worktree.

Control individual processes from a separate terminal:
```bash
overmind connect backend       # Attach for debugger/pry (Ctrl+b,d to detach)
overmind restart frontend      # Restart a single process
overmind stop worker           # Stop a specific process
```

There is also a `--volatile` flag for ephemeral runs with no persistent data: `bin/dev --volatile`.

### Option B: Separate terminals

Run the backend and frontend in different terminal windows:

```bash
# Terminal 1: Backend (Puma server)
bin/backend

# Terminal 2: Frontend (Vite dev server with HMR)
bin/frontend
```

Both scripts inherit environment variables from the shell or `.env` file (loaded by overmind).

### Option C: Production-style local

Build the frontend first and serve everything from the backend:
```bash
pnpm build
RACK_ENV=production bin/backend
```

This skips Vite's dev server and serves pre-built assets through Rack.

## Frontend Development

For HMR support, enable development mode in `etc/config.yaml`:

```yaml
:development:
  :enabled: true
  :frontend_host: 'http://localhost:5173'
```

See the [Installation Guide](https://docs.onetimesecret.com/en/self-hosting/installation/) for additional configuration details.

### Vite Development Server Security

For security, the Vite development server only allows connections from `localhost` by default. If you need to access the dev server from another machine on your network (e.g., a VM or a mobile device), you must explicitly configure `vite.config.ts` to allow your host.

**Example `vite.config.ts`:**

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

> **Security Warning:** Never set `server.hmr.host` to a public IP or expose the Vite dev server to the internet, as this can create security vulnerabilities.

## Redis/Valkey Setup

The application supports both Redis and Valkey servers. Use environment variables to specify which server and CLI tools to use:

```bash
# Set these in your shell profile or .env file
export VALKEY_SERVER=valkey-server  # or redis-server
export VALKEY_CLI=valkey-cli        # or redis-cli
```

If not set, defaults to `valkey-server` and `valkey-cli`.

**Package.json scripts:**
```bash
pnpm run database:start     # Start server in daemon mode
pnpm run database:start:fg  # Start server in foreground
pnpm run database:stop      # Stop server
pnpm run database:status    # Check if server is running
pnpm run database:clean     # Clean database
```

## Setting up Pre-commit Hooks

We use the `pre-commit` framework to maintain code quality and consistency.

1.  **Install pre-commit:**
    ```bash
    pip install pre-commit
    ```

2.  **Install the git hooks:**
    ```bash
    pre-commit install
    ```

This will run automated checks before each commit.


### Git JSON Merge Driver (Recommended)

This repository uses a custom merge driver for locale JSON files to automatically resolve conflicts:

1. Install dependencies: `pnpm install`
2. Configure Git (one-time setup):
   ```bash
   git config merge.json.driver "npx git-json-merge %A %O %B"
   git config merge.json.name "Custom 3-way merge driver for JSON files"
   ```

The driver automatically resolves conflicts when multiple branches modify different keys in the same locale file. If a conflict cannot be resolved automatically (e.g., same key modified on both sides), Git falls back to standard conflict markers.


## Docker-related Tips

### Container Name Already in Use

If you encounter an error like `docker: Error response from daemon: Conflict. The container name "/onetimesecret" is already in use`, it means a container with that name already exists. You can either remove the old container or start a new one with a different name.

```bash
# To remove the existing container
docker rm onetimesecret

# To start a new container with a different name
docker run --name onetimesecret-new ...
```

### Optimizing Docker Builds

To inspect the layers of a Docker image and identify opportunities for optimization, use the `docker history` command:

```bash
docker history onetimesecret --format "table {{.CreatedBy}}\t{{.Size}}"

# Or use dive for a more detailed analysis:
# brew install dive
# dive onetimesecret
```

### Docker Compose

Docker Compose configurations are included in this repository. The root `docker-compose.yml` includes a simple profile (app + Valkey) by default, with a full production stack (Caddy, RabbitMQ, workers) available:

```bash
cp --preserve --no-clobber .env.example .env
docker compose up
```

See `docker-compose.yml` for profile options and `docker/README.md` for complete setup documentation.
