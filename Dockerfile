# syntax=docker/dockerfile:1.15@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
# check=error=true

##
# ONETIME SECRET - DOCKER IMAGE
#
# Multi-stage build optimized for production deployment.
# See docs/docker.md for detailed usage instructions.
#
# For general project information, see README.md.
#
#
# BUILDING:
#
# Build the Docker image:
#
#     $ docker build -t onetimesecret .
#
# RUNNING:
#
#     # 1. Create a dedicated docker network
#     $ docker network create onetime-network
#
#     # 2. Start a Valkey/Redis container with persistent storage:
#     $ docker run -d --name onetime-maindb \
#         --network onetime-network \
#         -p 6379:6379 \
#         -v onetime_maindb_data:/data \
#         valkey/valkey
#
#     # 3. Set a unique secret:
#     $ openssl rand -hex 24
#     [Copy the output and save it somewhere safe]
#
#     $ echo -n "Enter a secret and press [ENTER]: "; read -s SECRET
#     [Paste the secret you copied from the openssl command]
#
#     # 4. Run the application:
#     $ docker run -p 3000:3000 --name onetime-app \
#         --network onetime-network \
#         -e SECRET=$SECRET \
#         -e SESSION_SECRET=$SESSION_SECRET \
#         -e REDIS_URL=redis://onetime-maindb:6379/0 \
#         --detach \
#         onetimesecret
#
# The app will be at http://localhost:3000. For more, see docs/docker.md.
#
#     # Double-check the persistent storage for redis
#     $ docker exec onetime-maindb ls -la /data
#
#     $ docker volume inspect onetime_maindb_data
#
#     # View application logs
#     $ docker logs onetime-app

ARG APP_DIR=/app
ARG PUBLIC_DIR=/var/www/public
ARG VERSION
ARG RUBY_IMAGE_TAG=3.4-slim-bookworm@sha256:1ca19bf218752c371039ebe6c8a1aa719cd6e6424b32d08faffdb2a6938f3241
ARG NODE_IMAGE_TAG=22@sha256:23c24e85395992be118734a39903e08c8f7d1abc73978c46b6bda90060091a49

##
# NODE: Node.js source for copying binaries
#
FROM docker.io/library/node:${NODE_IMAGE_TAG} AS node

##
# BASE: System dependencies and tools
#
# Installs system packages, updates RubyGems, and prepares the
# application's package management dependencies using a Debian
# Ruby 3.4 base image.
#
FROM docker.io/library/ruby:${RUBY_IMAGE_TAG} AS base

# Install system packages in a single layer
RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        libssl-dev \
        libffi-dev \
        libyaml-dev \
        libsqlite3-dev \
        libpq-dev \
        pkg-config \
        git \
        curl \
        xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Install yq (optimized for multi-arch)
# We use this for migrating config from v0.22 to v0.23.
RUN set -eux && \
    ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64) YQ_ARCH="amd64" ;; \
        arm64) YQ_ARCH="arm64" ;; \
        *) YQ_ARCH="amd64" ;; \
    esac && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    yq --version

# S6 overlay version
ARG S6_OVERLAY_VERSION=3.2.0.2

# Install S6 overlay for multi-process supervision
RUN set -eux && \
    ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64) S6_ARCH="x86_64" ;; \
        arm64) S6_ARCH="aarch64" ;; \
        armhf) S6_ARCH="armhf" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    cd /tmp && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" -o s6-overlay-noarch.tar.xz && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" -o s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf s6-overlay-arch.tar.xz && \
    rm -f s6-overlay-*.tar.xz

# Copy Node.js binaries (more efficient than full copy)
COPY --from=node \
    /usr/local/bin/node \
    /usr/local/bin/

COPY --from=node \
    /usr/local/lib/node_modules/npm \
    /usr/local/lib/node_modules/npm

# Create symlinks and install package managers
RUN set -eux && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    node --version && npm --version && \
    npm install -g pnpm && \
    pnpm --version

##
# DEPENDENCIES: Install application dependencies
#
# Sets up the necessary directories, installs additional
# system packages for userland, and installs the application's
# dependencies using the Base Layer as a starting point.
#
FROM base AS dependencies
ARG APP_DIR

WORKDIR ${APP_DIR}
ENV NODE_PATH=${APP_DIR}/node_modules

# Copy dependency manifests
COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml ./

# Install Ruby dependencies
# BUNDLE_WITHOUT excludes dev/test/optional gems from production image
ENV BUNDLE_WITHOUT="development:test:optional"

RUN set -eux && \
    bundle install --jobs "$(nproc)" --retry=3 && \
    bundle binstubs puma --force && \
    bundle clean --force

# Install Node.js dependencies (separate layer for better caching)
RUN set -eux && \
    pnpm install --frozen-lockfile --prod=false

##
# BUILD: Compile and prepare application assets
#
FROM dependencies AS build
ARG APP_DIR
ARG VERSION

WORKDIR ${APP_DIR}

# Copy application source
COPY public ./public
COPY src ./src
COPY package.json pnpm-lock.yaml tsconfig.json vite.config.ts \
     tailwind.config.ts eslint.config.ts ./

# Build application and generate schema
RUN set -eux && \
    pnpm run build && \
    pnpm prune --prod && \
    rm -rf node_modules ~/.npm ~/.pnpm-store && \
    npm uninstall -g pnpm

# Generate build metadata
RUN set -eux && \
    VERSION=$(node -p "require('./package.json').version") && \
    mkdir -p /tmp/build-meta && \
    echo "VERSION=${VERSION}" > /tmp/build-meta/version_env && \
    echo "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /tmp/build-meta/version_env && \
    date -u +%s > /tmp/build-meta/commit_hash.txt

##
# FINAL: Production-ready application image
#
FROM docker.io/library/ruby:${RUBY_IMAGE_TAG} AS final
ARG APP_DIR
ARG PUBLIC_DIR
ARG VERSION

LABEL org.opencontainers.image.version=${VERSION} \
      org.opencontainers.image.title="OneTime Secret" \
      org.opencontainers.image.description="Keep passwords out of your inboxes and chat logs with links that work only one time." \
      org.opencontainers.image.source="https://github.com/onetimesecret/onetimesecret"

RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        libpq5 \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

WORKDIR ${APP_DIR}

# Create non-root user for security
# Note: nologin shell blocks SSH/su, but docker exec still works for debugging:
#   docker exec -it container /bin/sh
RUN groupadd -g 1001 appuser && \
    useradd -r -u 1001 -g appuser -d ${APP_DIR} -s /sbin/nologin appuser

# Copy only runtime essentials from build stages
COPY --from=dependencies /usr/local/bin/yq /usr/local/bin/yq
COPY --from=dependencies /usr/local/bundle /usr/local/bundle

# Copy application files (using --chown to avoid extra layer)
COPY --chown=appuser:appuser --from=build ${APP_DIR}/public ./public
COPY --chown=appuser:appuser --from=build ${APP_DIR}/src ./src
COPY --chown=appuser:appuser --from=build /tmp/build-meta/commit_hash.txt ./.commit_hash.txt

# Copy runtime files
COPY --chown=appuser:appuser bin ./bin
COPY --chown=appuser:appuser apps ./apps
COPY --chown=appuser:appuser etc/ ./etc/
COPY --chown=appuser:appuser lib ./lib
COPY --chown=appuser:appuser scripts/entrypoint.sh ./bin/
COPY --chown=appuser:appuser scripts/entrypoint-jobs.sh ./bin/
COPY --chown=appuser:appuser scripts/update-version.sh ./bin/
COPY --chown=appuser:appuser --from=dependencies ${APP_DIR}/bin/puma ./bin/puma
COPY --chown=appuser:appuser package.json config.ru Gemfile Gemfile.lock ./

# Copy S6 service definitions (as root for proper ownership)
USER root
COPY --chown=root:root scripts/s6-rc.d /etc/s6-overlay/s6-rc.d

# Set permissions on service scripts
RUN find /etc/s6-overlay/s6-rc.d -type f -name "run" -exec chmod +x {} \; && \
    find /etc/s6-overlay/s6-rc.d -type f -name "finish" -exec chmod +x {} \; && \
    find /etc/s6-overlay/s6-rc.d -type f -name "up" -exec chmod +x {} \;

# Switch back to appuser
USER appuser

# Set production environment
ENV RACK_ENV=production \
    ONETIME_HOME=${APP_DIR} \
    PUBLIC_DIR=${PUBLIC_DIR} \
    RUBY_YJIT_ENABLE=1 \
    SERVER_TYPE=puma \
    BUNDLE_WITHOUT="development:test:optional" \
    PATH=${APP_DIR}/bin:$PATH

# S6 configuration
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_VERBOSITY=2

# Ensure config files exist (preserve existing if mounted)
# Copies all default config files from etc/defaults/*.defaults.* to etc/*
# removing the .defaults suffix. For example:
#   etc/defaults/config.defaults.yaml -> etc/config.yaml
#   etc/defaults/auth.defaults.yaml -> etc/auth.yaml
#   etc/defaults/logging.defaults.yaml -> etc/logging.yaml
# The --no-clobber flag ensures existing files are not overwritten.
RUN set -eux && \
    for file in etc/defaults/*.defaults.*; do \
        if [ -f "$file" ]; then \
            target="etc/$(basename "$file" | sed 's/\.defaults//')"; \
            cp --preserve --no-clobber "$file" "$target"; \
        fi; \
    done && \
    cp --preserve --no-clobber etc/examples/puma.example.rb etc/puma.rb && \
    chmod +x bin/entrypoint.sh bin/entrypoint-jobs.sh bin/update-version.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://127.0.0.1:3000/api/v2/status || exit 1

# Run as non-root user
USER appuser

# About the interplay between the Dockerfile CMD, ENTRYPOINT,
# and the Docker Compose command settings:
#
# With S6 overlay:
# - ENTRYPOINT is /init (S6's PID 1 init system)
# - CMD is empty by default (S6 starts all services defined in s6-rc.d/user bundle)
# - To run specific services only, override CMD in docker-compose.yaml:
#   - For web only: command: ["bin/entrypoint.sh"]
#   - For jobs only: command: ["bin/entrypoint-jobs.sh"]
#   - For all services: Use default (no command override)
#
# S6 supervises all services, providing:
# - Automatic restart on crash
# - Graceful shutdown coordination
# - Dependency management
# - Proper signal handling

ENTRYPOINT ["/init"]
CMD []
