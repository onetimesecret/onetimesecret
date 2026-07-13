# Docker Deployment (Updated: 2026-07-10)

All Docker Compose configuration is maintained in this repository.
The separate [onetimesecret/docker-compose](https://github.com/onetimesecret/docker-compose)
repository is archived as of v0.24.

## Compose Files

| File                                        | Services                                              | Use Case                                       |
| ------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------- |
| `docker-compose.yml`                        | Include wrapper                                       | Root entry point — defaults to simple          |
| `docker/compose/docker-compose.simple.yml`  | App + Valkey                                          | Development, testing, minimal deployments      |
| `docker/compose/docker-compose.full.yml`    | Caddy + App + Valkey + RabbitMQ + Workers + Scheduler | Full production                                |
| `docker/compose/docker-compose.mailpit.yml` | Mailpit (SMTP capture)                                | Email testing — include alongside simple       |
| `compose.test.yml` (repo root)              | Valkey/Postgres/RabbitMQ on 21xx host ports           | Test lanes only (`tests/lanes/README.md`) — never for deployment |

Naming convention: deployment compose files are `docker-compose.*.yml` —
the stacks under `docker/compose/` plus the root `docker-compose.yml`
include wrapper. The root `compose.test.yml` is test-lane service
infrastructure with its own port scheme; it never runs the app.

## Switching Stacks

The stacks are separate files, selected one of two ways (they are not
Compose "profiles" — no `--profile` flag is involved):

1. Edit the `include` in the root `docker-compose.yml`:

   ```yaml
   include:
     # - path: docker/compose/docker-compose.simple.yml
     - path: docker/compose/docker-compose.full.yml
   ```

2. Or skip the wrapper and point Compose at a stack directly (this is
   what CI does):

   ```bash
   docker compose -f docker/compose/docker-compose.full.yml up
   ```

## Quick Start

```bash
[ -f .env ] || cp .env.example .env
echo "SECRET=$(openssl rand -hex 32)" >> .env
docker compose up
```

Then create an admin account (the app service is named `app` in both
stacks):

```bash
docker compose exec app bin/ots customers create me@example.com --role colonel
```

More forms (plain `docker exec`, bare-metal, API tokens) and the
`AUTH_AUTOVERIFY`/SMTP signup caveat:
[Create your first account](../README.md#create-your-first-account) in the
root README.

## Environment Variables

| Variable                            | Stack        | Required                             | Default                    | Notes                                                                     |
| ----------------------------------- | ------------ | ------------------------------------ | -------------------------- | ------------------------------------------------------------------------- |
| `SECRET`                            | both         | yes (compose aborts if empty)        | —                          | Root secret; HKDF input for derived keys. Back it up.                      |
| `AUTHENTICATION_MODE`               | both         | no                                   | `simple` / `full`          | Set per stack by the compose files.                                        |
| `AUTH_SECRET`                       | full         | yes for full auth (TOTP, login tokens) | —                        | Independent secret; cannot be re-derived. Back it up.                      |
| `ACCOUNT_ID_SECRET`                 | full         | yes in production (>= 32 bytes)      | —                          | Obfuscates account IDs in email links and remember-me cookies.             |
| `ARGON2_SECRET`                     | full         | strongly recommended                 | —                          | Password pepper; changing it invalidates all password hashes.              |
| `SESSION_SECRET`, `IDENTIFIER_SECRET` | both       | no                                   | derived from `SECRET`      | Only set to override HKDF derivation.                                      |
| `FEDERATION_SECRET`                 | both         | multi-region only                    | —                          | Must be identical across regions.                                          |
| `DOMAIN`, `CERTIFICATE_EMAIL`       | full (proxy) | yes for real TLS                     | `localhost` / `admin@example.com` | Let's Encrypt issuance via Caddy.                                    |
| `RABBITMQ_USER`, `RABBITMQ_PASS`    | full         | change for production                | `guest` / `guest`          | AMQP credentials; also embedded in `RABBITMQ_URL`.                          |
| `JOBS_ENABLED`                      | full         | no                                   | `false`                    | See [Background Jobs](#background-jobs-jobs_enabled).                       |
| `OTS_IMAGE_TAG`                     | both         | no                                   | pinned release             | See [Image Version](#image-version-ots_image_tag).                          |
| `RACK_ENV`                          | both         | no                                   | `production`               |                                                                             |

## Background Jobs (JOBS_ENABLED)

Off by default. With `JOBS_ENABLED` unset or `false`, the `worker-email`
and `scheduler` services sit idle and the web app sends email
synchronously in-process — the full stack works without touching this.

Set `JOBS_ENABLED=true` to have the web app publish jobs to RabbitMQ,
where `worker-email` consumes the `email` queue. The workers boot the
full application, so they read the same `.env`; `RABBITMQ_URL` is wired
by the compose file and the worker exits if RabbitMQ is unreachable
(compose restarts it). Scheduled jobs additionally require
`JOBS_SCHEDULER_ENABLED=true` for the `scheduler` service to have
anything to do.

## Image Version (OTS_IMAGE_TAG)

The compose files default `OTS_IMAGE_TAG` to a pinned release — the same
version the root README's `docker run` quick start uses — rather than
`latest`, so a fresh `docker compose up` is reproducible. Override it in
`.env` or inline:

```bash
OTS_IMAGE_TAG=latest docker compose up
```

At release time, bump the pinned tag in the root README and in the
`docker/compose/*.yml` defaults together (grep for the old version).

## Data Persistence

- Valkey data (secrets, sessions) lives in the `onetime_maindb_data`
  named volume in both stacks.
- The full stack keeps `/app/data` (the sqlite `auth.db` for full
  authentication mode) in the `onetime_app_data` named volume, shared by
  the app, worker, and scheduler services. The simple stack has no
  `/app/data` mount — simple mode stores nothing there.

To keep `/app/data` in a host directory instead (e.g. for host-visible
backups), replace `app-data:/app/data` with `../../data:/app/data` on
the `app`, `worker-email`, and `scheduler` services. On Linux the
directory must be writable by the container user first:

```bash
mkdir -p data && sudo chown -R 1001:1001 data   # container runs as uid 1001
```

Migrating an existing bind-mount deployment to the named volume: copy
`auth.db` in after the first start, e.g.
`docker compose cp ./data/auth.db app:/app/data/auth.db`, then restart.

Note: the named volume self-initializes with correct (uid 1001)
ownership only on images that ship a `/app/data` directory. On older
published images, pre-create the ownership once:
`docker compose run --rm --user root app chown appuser:appuser /app/data`.

## Debugging Valkey

The simple stack publishes Valkey on `127.0.0.1:6379` (loopback only)
for host tooling:

```bash
valkey-cli -h 127.0.0.1 -p 6379
```

If that collides with a Redis already on your host, delete the `ports`
block from the `maindb` service — no published port is needed for the
stack itself, and you can always debug from inside the network:

```bash
docker compose exec maindb valkey-cli
```

The full stack does not publish Valkey at all (`expose` only).

## Building Images

For standalone builds (Docker Bake, Podman, CI pipelines), see [Build Architecture](../docs/architecture/build-architecture.md).

## Branding Overlay

Generated brand packs live under `public/branding/<name>/` (gitignored). Bake
one into the image with `--build-arg BRAND_PACK=<name>` — the `Dockerfile`
copies it over `public/web/` after the Vite build (look for `NOTICE: applied
brand pack overlay`) and fails the build if the pack was never generated. No
build arg = neutral defaults. The same pack can also be selected at runtime via
`BRAND_PACK` / `BRAND_ASSETS_DIR` (no rebuild).

Full asset list and other ways to override:
[branding-favicon](../docs/product/branding-favicon.md).
