# syntax=docker/dockerfile:1.15@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
# check=error=true

##
# ONETIME SECRET - DOCKER IMAGE
#
# Multi-stage build optimized for production deployment.
# See docs/DOCKER.md for detailed usage instructions.
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
#     # 1. Start a Valkey/Redis container:
#     $ docker run -d --name db -p 6379:6379 valkey/valkey
#
#     # 2. Set a unique secret:
#     $ openssl rand -hex 24
#     [Copy the output and save it somewhere safe]
#
#     $ echo -n "Enter a secret and press [ENTER]: "; read -s SECRET
#     [Paste the secret you copied from the openssl command]
#
#     # 3. Run the application:
#     $ docker run -p 3000:3000 -d --name onetimesecret \
#         -e SECRET=$SECRET \
#         -e REDIS_URL=redis://host.docker.internal:6379/0 \
#         onetimesecret
#
# The app will be at http://localhost:3000. For more, see docs/DOCKER.md.
#

ARG APP_DIR=/app
ARG VERSION
ARG RUBY_IMAGE_TAG=3.4-slim-bookworm@sha256:dd8c06af4886548264f4463ee2400fd6be641b0562c8f681e490d759632078f5
ARG NODE_IMAGE_TAG=22@sha256:afff6d8c97964a438d2e6a9c96509367e45d8bf93f790ad561a1eaea926303d9

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
        libffi-dev \
        libyaml-dev \
        git \
        curl && \
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
    gem install bundler && \
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
# NOTE: We can't use the more aggresive `--local deployment true` to reduce
# the image size further b/c it requires having all git dependencies installed.
# Can revisit if/when we can use a released rspec version.
RUN set -eux && \
    bundle config set --local without 'development test' && \
    bundle config set --local jobs "$(nproc)" && \
    bundle install --retry=3 && \
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
COPY templates ./templates
COPY src ./src
COPY package.json pnpm-lock.yaml tsconfig.json vite.config.ts \
     postcss.config.mjs tailwind.config.ts eslint.config.ts ./

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
ARG VERSION

LABEL org.opencontainers.image.version=${VERSION} \
      org.opencontainers.image.title="OneTime Secret" \
      org.opencontainers.image.description="Keep passwords out of your inboxes and chat logs with links that work only once." \
      org.opencontainers.image.source="https://github.com/onetimesecret/onetimesecret"

WORKDIR ${APP_DIR}

# # Create non-root user for security
# RUN set -eux && \
#     groupadd -g 1001 appuser && \
#     useradd -r -u 1001 -g appuser -d ${APP_DIR} -s /bin/bash appuser && \
#     chown -R appuser:appuser ${APP_DIR}

# Now we can switch to the non-root user for the rest of the commands
# WARNING: Changing the user adds a big, new layer to the image.
# USER appuser

# Copy only runtime essentials from build stages
COPY --from=dependencies /usr/local/bin/yq /usr/local/bin/yq
COPY --from=dependencies /usr/local/bundle /usr/local/bundle

# Copy application files
COPY --from=build ${APP_DIR}/public ./public
COPY --from=build ${APP_DIR}/templates ./templates
COPY --from=build ${APP_DIR}/src ./src
COPY --from=build /tmp/build-meta/commit_hash.txt ./.commit_hash.txt

# Copy runtime files
COPY bin ./bin
COPY apps ./apps
COPY etc/ ./etc/
COPY lib ./lib
COPY migrations ./migrations
COPY scripts/entrypoint.sh ./bin/
COPY scripts/update-version.sh ./bin/
COPY package.json config.ru Gemfile Gemfile.lock ./

# Set production environment
ENV RACK_ENV=production \
    ONETIME_HOME=${APP_DIR} \
    RUBY_YJIT_ENABLE=1 \
    PATH=${APP_DIR}/bin:$PATH

# Ensure config files exist (preserve existing if mounted)
# Copies the default config files into place if they don't
# already exist. If a file does exist, nothing happens. For
# example, if the config file has been previously copied
# (and modified) the "--no-clobber" argument prevents
# those changes from being overwritten.
RUN set -eux && \
    cp --preserve --no-clobber etc/defaults/config.defaults.yaml etc/config.yaml && \
    chmod +x bin/entrypoint.sh bin/update-version.sh

EXPOSE 3000

# HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
#     CMD curl -f http://localhost:3000/api/v2/status || exit 1

# About the interplay between the Dockerfile CMD, ENTRYPOINT,
# and the Docker Compose command settings:
#
# 1. The CMD instruction in the Dockerfile sets the default command to
# be executed when the container is started.
#
# 2. The command setting in the Docker Compose configuration overrides
# the CMD instruction in the Dockerfile.
#
# 3. Using the CMD instruction in the Dockerfile provides a fallback
# command, which can be useful if no specific command is set in the
# Docker Compose configuration.
CMD ["bin/entrypoint.sh"]
