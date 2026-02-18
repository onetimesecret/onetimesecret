# Docker Deployment (Updated: 2026-02-18)

All Docker Compose configuration is maintained in this repository.
The separate [onetimesecret/docker-compose](https://github.com/onetimesecret/docker-compose)
repository is archived as of v0.24.

## Compose Files

| File | Services | Use Case |
|------|----------|----------|
| `docker-compose.yml` | Include wrapper | Root entry point — defaults to simple |
| `docker/compose/docker-compose.simple.yml` | App + Valkey | Development, testing, minimal deployments |
| `docker/compose/docker-compose.full.yml` | Caddy + App + Valkey + RabbitMQ + Workers + Scheduler | Full production |

Switch stacks by editing the `include` in the root `docker-compose.yml`:

```yaml
include:
  # - path: docker/compose/docker-compose.simple.yml
  - path: docker/compose/docker-compose.full.yml
```

## Quick Start

```bash
cp --preserve --no-clobber .env.example .env
echo "SECRET=$(openssl rand -hex 32)" >> .env
docker compose up
```

The full stack requires additional env vars — see the compose file for required secrets.
