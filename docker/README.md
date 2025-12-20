# Docker Deployment (Updated: 2025-11-09)

Three-tier stack: Caddy (TLS + proxy) → App (Puma) → Valkey (sessions,accounts,secrets).

## Architecture

```
Internet → Caddy (80/443) → App (3000) → Redis (6379)
           └─ TLS             └─ Puma      └─ Valkey
           └─ Static Assets   └─ Rack      └─ AOF/RDB
```

## Quick Start

```bash
# Setup
cp --preserve --no-clobber .env.example .env
cp --preserve --no-clobber ./etc/examples/Caddyfile-example ./etc/Caddyfile


# Add secrets to your .env file
echo "SECRET=$(openssl rand -hex 32)" >> .env
echo "SESSION_SECRET=$(openssl rand -hex 32)" >> .env

# Configure (edit .env)
DOMAIN=localhost
CERTIFICATE_EMAIL=dev@localhost
RACK_ENV=development

# Start
docker-compose up
```

Access: http://localhost

## Production

Edit `.env`:
```bash
DOMAIN=secrets.example.com
CERTIFICATE_EMAIL=sandoval@example.com
RACK_ENV=production
SECRET=<generated>
SESSION_SECRET=<generated>
REDIS_URL=redis://redis:6379/0
```

Start detached:
```bash
docker-compose up -d
```


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
