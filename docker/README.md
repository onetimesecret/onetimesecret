# Docker Deployment (Updated: 2026-02-18)

All Docker Compose configuration is maintained in this repository.
The separate [onetimesecret/docker-compose](https://github.com/onetimesecret/docker-compose)
repository is archived as of v0.24.

## Compose Files

| File                                       | Services                                              | Use Case                                  |
| ------------------------------------------ | ----------------------------------------------------- | ----------------------------------------- |
| `docker-compose.yml`                       | Include wrapper                                       | Root entry point — defaults to simple     |
| `docker/compose/docker-compose.simple.yml` | App + Valkey                                          | Development, testing, minimal deployments |
| `docker/compose/docker-compose.full.yml`   | Caddy + App + Valkey + RabbitMQ + Workers + Scheduler | Full production                           |

Switch stacks by editing the `include` in the root `docker-compose.yml`:

```yaml
include:
  # - path: docker/compose/docker-compose.simple.yml
  - path: docker/compose/docker-compose.full.yml
```

## Quick Start

```bash
cp -n .env.example .env
echo "SECRET=$(openssl rand -hex 32)" >> .env
docker compose up
```

The full stack requires additional env vars — see the compose file for required secrets.

## Building Images

For standalone builds (Docker Bake, Podman, CI pipelines), see [Build Architecture](../docs/architecture/build-architecture.md).

## Branding Overlay

`docker/public/` bakes favicon/branding assets into the image at build time.
Empty by default (`.gitignore` only). Drop replacement assets in before
building — the `Dockerfile` copies them into `public/web/` after the Vite build
(look for `NOTICE: applied docker/public overlay`). Include only the files you
want to override; the rest fall back to neutral defaults.

Full asset list and other ways to override:
[branding-favicon](../docs/product/branding-favicon.md).
