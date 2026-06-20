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
cp --preserve --update=none .env.example .env
echo "SECRET=$(openssl rand -hex 32)" >> .env
docker compose up
```

The full stack requires additional env vars — see the compose file for required secrets.

## Building Images

For standalone builds (Docker Bake, Podman, CI pipelines), see [Build Architecture](../docs/architecture/build-architecture.md).

## Branding Overlay

`docker/public/` is the build-time favicon/branding override mechanism. It is
**empty by default** (`.gitignore` only). To bake your own brand into the image,
drop replacement assets directly into `docker/public/` before building:


```
favicon.ico
favicon.svg
apple-touch-icon.png
icon-192.png
icon-512.png
safari-pinned-tab.svg
site.webmanifest
social-preview.png
```


Include only the files you want to override; the rest fall back to the neutral
defaults. At build time the `Dockerfile` copies them into `public/web/` (the
served document root) after the Vite build — look for `NOTICE: applied
docker/public overlay`.

No-rebuild alternatives: runtime URL overrides (`BRAND_FAVICON_URL`,
`BRAND_APPLE_TOUCH_ICON_URL`, `BRAND_OG_IMAGE_URL`, `BRAND_LOGO_URL`, …) or
mounting replacement files over `public/web/...` via a volume. Per-custom-domain
branding always takes precedence over these site-level defaults.

See [branding-favicon](../docs/product/branding-favicon.md).
