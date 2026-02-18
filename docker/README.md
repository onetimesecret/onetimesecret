# Docker Deployment (Updated: 2026-02-18)

All Docker Compose configuration is maintained in this repository.
The separate [onetimesecret/docker-compose](https://github.com/onetimesecret/docker-compose)
repository is archived as of v0.24.

## Compose Files

| File | Services | Use Case |
|------|----------|----------|
| `docker-compose.yml` | Include wrapper | Root entry point — defaults to simple |
| `docker/docker-compose.simple.yml` | App + Valkey | Development, testing, or minimal deployments |
| `docker/docker-compose.full.yml` | Caddy + App + Valkey + RabbitMQ + Worker + Scheduler | Full production deployment |

Switch between them by editing the `include` in the root `docker-compose.yml`.

## Architecture (Full Stack)

```
Internet → Caddy (80/443) → App (3000) → Redis (6379)
           └─ TLS             └─ Puma      └─ Valkey
           └─ Static Assets   └─ Rack      └─ AOF/RDB
```

## Quick Start (Simple)

The default `docker compose up` runs the simple stack (App + Valkey):

```bash
cp --preserve --no-clobber .env.example .env
echo "SECRET=$(openssl rand -hex 32)" >> .env

docker compose up
```

Access: http://localhost:3000

## Full Production Stack

Edit `docker-compose.yml` to switch the include:

```yaml
include:
  # - path: docker/docker-compose.simple.yml
  - path: docker/docker-compose.full.yml
```

Then configure and start:

```bash
cp --preserve --no-clobber .env.example .env
cp --preserve --no-clobber ./etc/examples/Caddyfile-example ./etc/Caddyfile

echo "SECRET=$(openssl rand -hex 32)" >> .env
echo "SESSION_SECRET=$(openssl rand -hex 32)" >> .env

# Edit .env
DOMAIN=secrets.example.com
CERTIFICATE_EMAIL=admin@example.com
RACK_ENV=production

docker compose up -d
```

Access: https://secrets.example.com


## Operations

```bash
# Logs
docker-compose logs -f [app|proxy|redis]

# Restart
docker-compose restart [service]

# Rebuild
docker-compose up -d --build

# Shell access
docker-compose exec app /bin/bash
docker-compose exec redis valkey-cli

# Status
docker-compose ps
curl http://localhost/api/v2/status
```

## Backup/Restore

```bash
# Backup
docker-compose exec redis valkey-cli BGSAVE
docker cp onetime-redis:/data/onetime.rdb backup-$(date +%Y%m%d).rdb

# Restore
docker-compose down
docker run --rm -v onetime_maindb_data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/redis-backup.tar.gz -C /data
docker-compose up -d
```

## Cleanup

```bash
# Stop containers (volumes preserved)
docker-compose down

# Stop and remove all data
docker-compose down -v
```
