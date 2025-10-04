# Onetime Secret - Docker Deployment Guide

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

Onetime Secret creates single-use URLs for secure information sharing. This guide covers Docker deployment options from quick testing to production setups.

> [!NOTE]
> Pre-built images are available from [GitHub Container Registry](https://github.com/onetimesecret/onetimesecret/pkgs/container/onetimesecret) and [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret). Most users can skip the "Building the Image" section.

> [!NOTE]
> For our "lite" Docker image offering an ephemeral option, see [DOCKER-lite.md](DOCKER-lite.md).

## Available Images

**Pre-built options:**
```bash
# GitHub Container Registry (recommended)
docker pull ghcr.io/onetimesecret/onetimesecret:latest

# Docker Hub
docker pull onetimesecret/onetimesecret:latest

# Lite version (includes Valkey/Redis, for ephemeral use)
docker pull ghcr.io/onetimesecret/onetimesecret-lite:latest
```

**Build locally:**
```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
docker build -t onetimesecret .
```

**Multi-platform builds:**
```bash
docker buildx build --platform=linux/amd64,linux/arm64 . -t onetimesecret
```

## Quick Start

For quick testing, run Onetime Secret with a few commands:

**1. Start Valkey/Redis:**
```bash
docker run -d --name valkey -p 6379:6379 valkey/valkey
```

**2. Generate and store a secret key:**
```bash
# Generate a persistent secret key
openssl rand -hex 32 > .ots_secret
chmod 600 .ots_secret
echo "Secret key saved to .ots_secret (keep this file secure!)"
```

**3. Run the application:**
```bash
docker run -p 3000:3000 -d --name onetimesecret \
    -e SECRET="$(cat .ots_secret)" \
    -e VALKEY_URL=redis://host.docker.internal:6379/0 \
    -e HOST=localhost:3000 \
    -e AUTH_REQUIRED=false \
    -e SSL=false \  # ⚠️ WARNING: Set SSL=true for production deployments
    onetimesecret/onetimesecret:latest
```

Note: Either `VALKEY_URL` or `REDIS_URL` variables can be used to point to the running Valkey/Redis instance.

> [!INFO]
> `host.docker.internal` is supported in Docker 20.10+ on all platforms. For older versions on Linux, use `--add-host=host.docker.internal:host-gateway` or the host's IP address.

**4. Access:** http://localhost:3000

## Configuration File Setup

For production or persistent setups, use a configuration file to avoid exposing secrets in shell history:

**1. Create environment file:**
```bash
cp .env.example .env
```

**2. Edit your configuration:**
```bash
nano .env
```

Set essential variables:
```bash
SECRET=your-secure-random-key-from-openssl-rand-hex-32
VALKEY_URL=redis://host:6379/0
AUTH_REQUIRED=true
SSL=true
```

**3. Run with environment file:**
```bash
docker run -p 3000:3000 -d --name onetimesecret \
    --env-file .env \
    onetimesecret/onetimesecret:latest
```

## Docker Compose

For complete multi-container setups with dependencies managed automatically:

[Docker Compose repository](https://github.com/onetimesecret/docker-compose/) - configurations for production and development environments.

## Configuration

Configuration uses environment variables or `etc/config.yaml`. The Docker image copies defaults from `etc/defaults/config.defaults.yaml` on startup.

### Configuration Methods

**Environment Variables (Recommended):**
Use `.env` file with `--env-file` flag for common settings.

**Custom config.yaml (Advanced):**
Mount your own configuration file for complete control:

```bash
docker run -p 3000:3000 -d --name onetimesecret \
    -v /path/to/custom-config.yaml:/app/etc/config.yaml \
    onetimesecret/onetimesecret:latest
```

> [!WARNING]
> Custom config files must include all necessary settings, including strong `SECRET` and correct `VALKEY_URL`.

### Essential Environment Variables

**Required:**
- `SECRET`: Long, random encryption key (use `openssl rand -hex 32`)
- `VALKEY_URL`: Valkey/Redis connection URL

**Common:**
- `HOST`: Service hostname
- `SSL`: Use HTTPS links (`true`/`false`)
- `AUTH_REQUIRED`: Require login for secret creation
- `PASSPHRASE_REQUIRED`: Require passphrases for secrets
- `COLONEL`: Admin account email

## System Requirements

- **OS**: Recent Linux distro or *BSD
- **Database**: Valkey/Redis 5+
- **Minimum**: 2 CPU cores, 1GB RAM, 4GB disk

## Production Checklist

Ensure your production deployment is secure and robust:

- **[ ] Strong Secret Key:** Generate with `openssl rand -hex 32` and store securely
- **[ ] Secure Database:** Use Redis/Valkey authentication and network restrictions
- **[ ] Database Persistence:** Enable AOF or RDB snapshots for data durability
- **[ ] Correct Domain:** Set `HOST` to your domain and `SSL=true`
- **[ ] Specific Version:** Pin to version tag (e.g., `v0.22.6`) instead of `latest`
- **[ ] Secure Configuration:** Use `.env` files or mounted config, not command-line secrets

**Production example:**
```bash
docker run -p 3000:3000 -d --name onetimesecret \
  --env-file .production.env \
  -v /var/onetimesecret/config.yaml:/app/etc/config.yaml \
  onetimesecret/onetimesecret:v0.22.6
```

## Updating

Update your deployment to the latest version:

**1. Pull latest image:**
```bash
docker pull onetimesecret/onetimesecret:latest
```

**2. Replace container:**
```bash
docker stop onetimesecret
docker rm onetimesecret
```

**3. Start with updated image:**
Use the same run command from your initial setup.

> [!INFO]
> Version tags correspond to [GitHub releases](https://github.com/onetimesecret/onetimesecret/releases). Using specific versions ensures consistent deployments and easier rollbacks.

## Support

- **Issues**: [GitHub Issues](https://github.com/onetimesecret/onetimesecret/issues)
- **Documentation**: Check `docs/` directory for detailed guides
- **Security**: Review `SECURITY.md` for security considerations
