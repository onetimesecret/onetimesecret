# Docker Variants

Alternative Docker builds for specific deployment scenarios.

## Lite Image

Self-contained container with both the Onetime Secret application and Redis. Ephemeral by design - all data is lost when the container stops. This is a security feature.

**Use case**: Quick testing, demos, development

### Build

```bash
docker build -t onetimesecret-lite -f docker/variants/lite.dockerfile .
```

### Run

```bash
docker run --rm -p 7143:3000 --name onetimesecret-lite onetimesecret-lite:latest
```

Access: http://localhost:7143

### Pre-built Image

```bash
docker pull ghcr.io/onetimesecret/onetimesecret-lite:latest
```

> **Warning**: Not for production. No data persistence. For production deployments, use the main Docker image with a separate Redis/Valkey instance.

## Caddy Proxy Image

Custom Caddy build with rate limiting, security, and DNS plugins for automatic TLS.

**Use case**: Production reverse proxy with Let's Encrypt

### Build

```bash
# Default: Caddy 2.10.2 with Cloudflare DNS
docker build -f docker/variants/caddy.dockerfile -t onetime-caddy:v2.10.2 .

# With different DNS module (e.g., Route53)
CADDY_VERSION=v2.10.2; docker build -f docker/variants/caddy.dockerfile \
  --build-arg DNS_MODULE=route53 \
  --build-arg CADDY_VERSION=${CADDY_VERSION} \
  -t onetime-caddy:${CADDY_VERSION} .
```

### Run

```bash
docker network create onetime-network

docker run \
  --name onetime-proxy \
  --network onetime-network \
  -p 80:80 -p 443:443 \
  -v $PWD/etc/examples/Caddyfile-example:/etc/caddy/Caddyfile \
  -v onetime_caddy_data:/data \
  -e CERTIFICATE_EMAIL=admin@example.com \
  -e UPSTREAM_HOST=onetime-app \
  -e UPSTREAM_PORT=3000 \
  -e DOMAIN=secrets.example.com \
  --restart unless-stopped \
  --detach \
  onetime-caddy:v2.10.2
```

### Included Plugins

- `caddy-ratelimit` - Request rate limiting
- `caddy-security` - Security middleware
- `transform-encoder` - Log transformation
- `caddy-dns/*` - DNS challenge support (configurable)

See available DNS modules: https://github.com/orgs/caddy-dns/repositories

## See Also

- [Main Docker docs](../README.md) - Standard deployment
- [S6 overlay docs](../s6/README.md) - Multi-process supervision
