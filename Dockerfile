# syntax=docker/dockerfile:1.15@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
# check=error=true

##
# ONETIME SECRET - DOCKER IMAGE (2025-11-27)
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


##
# BUILDER LAYER
#
# Installs system packages, updates RubyGems, and prepares the
# application's package management dependencies using a Debian
# Ruby 3 base image.
#
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/opt/onetime
ARG VERSION

FROM docker.io/library/ruby:3.4-slim-bookworm@sha256:6785e74b2baeb6a876abfc2312b590dac1ecd1a2fe25fe57c3aa4d9ad53224d7 AS base

# Limit to packages needed for the system itself
ARG PACKAGES="build-essential rsync netcat-openbsd libffi-dev libyaml-dev git curl"

# Fast fail on errors while installing system packages
RUN set -eux \
  && apt-get update \
  && apt-get install -y $PACKAGES \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install yq (optimized for multi-arch)
# Used for migrating config from symbol keys to string keys (v0.22 to v0.23+)
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

# Copy Node.js and npm from the official image
COPY --from=docker.io/library/node:22@sha256:8739e532180cfe09e03bbb4545fc725b044c921280532d7c9c1480ba2396837e /usr/local/bin/node /usr/local/bin/
COPY --from=docker.io/library/node:22@sha256:8739e532180cfe09e03bbb4545fc725b044c921280532d7c9c1480ba2396837e /usr/local/lib/node_modules /usr/local/lib/node_modules

# Create necessary symlinks
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Verify Node.js and npm installation
RUN node --version && npm --version

# Install necessary tools
RUN set -eux \
  && gem install bundler \
  && npm install -g pnpm

##
# DEPENDENCIES LAYER
#
# Sets up the necessary directories, installs additional
# system packages for userland, and installs the application's
# dependencies using the Base Layer as a starting point.
#
FROM base AS app_deps
ARG CODE_ROOT
ARG ONETIME_HOME
ARG VERSION

# Create the directories that we need in the following image
RUN set -eux \
  && echo "Creating directories" \
  && mkdir -p $CODE_ROOT $ONETIME_HOME/{log,tmp}

WORKDIR $CODE_ROOT

ENV NODE_PATH=$CODE_ROOT/node_modules

# Install the dependencies into the environment image
COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-lock.yaml ./

RUN set -eux \
  && bundle config set --local without 'development test' \
  && bundle update --bundler \
  && bundle install

# Put the npm depdenencies in a separate layer to avoid
# rebuilding the gems when the package.json is updated.
RUN set -eux \
  && pnpm install --frozen-lockfile

##
# BUILD LAYER
#
FROM app_deps AS build
ARG CODE_ROOT
ARG VERSION

WORKDIR $CODE_ROOT

COPY public $CODE_ROOT/public
COPY templates $CODE_ROOT/templates
COPY src $CODE_ROOT/src
COPY package.json pnpm-lock.yaml tsconfig.json vite.config.ts postcss.config.mjs tailwind.config.ts eslint.config.ts ./

# Remove pnpm after use
RUN set -eux \
  && pnpm run build \
  && pnpm prune --prod \
  && rm -rf node_modules \
  && npm uninstall -g pnpm

# Create both version and commit hash files while we can
RUN VERSION=$(node -p "require('./package.json').version") \
    && mkdir -p /tmp/build-meta \
    && echo "VERSION=$VERSION" > /tmp/build-meta/version_env \
    && if [ ! -f /tmp/build-meta/commit_hash.txt ]; then \
      date -u +%s > /tmp/build-meta/commit_hash.txt; \
    fi

##
# APPLICATION LAYER (FINAL)
#
FROM ruby:3.4-slim-bookworm@sha256:fdadeae7d74a179b236dc991a43958c5f09545569d0d8df89051d14f9ee40c15 AS final
ARG CODE_ROOT
ARG VERSION
LABEL org.opencontainers.image.version=$VERSION

WORKDIR $CODE_ROOT

## Copy only necessary files from previous stages
COPY --from=base /usr/local/bin/yq /usr/local/bin/yq
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build $CODE_ROOT/public $CODE_ROOT/public
COPY --from=build $CODE_ROOT/templates $CODE_ROOT/templates
COPY --from=build $CODE_ROOT/src $CODE_ROOT/src
COPY bin $CODE_ROOT/bin
COPY apps $CODE_ROOT/apps
COPY etc $CODE_ROOT/etc
COPY lib $CODE_ROOT/lib
COPY scripts/entrypoint.sh ./bin/
COPY scripts/check-migration-status.sh ./bin/
COPY scripts/update-version.sh ./bin/
COPY migrations $CODE_ROOT/migrations
COPY package.json config.ru Gemfile Gemfile.lock $CODE_ROOT/

# Copy build stage metadata files
COPY --from=build /tmp/build-meta/commit_hash.txt $CODE_ROOT/.commit_hash.txt

# See: https://fly.io/docs/rails/cookbooks/deploy/
ENV RUBY_YJIT_ENABLE=1

# Explicitly setting the Rack environment to production directs
# the application to use the pre-built JS/CSS assets in the
# "public/web/dist" directory. In dev mode, the application
# expects a vite server to be running on port 5173 and will
# attempt to connect to that server for each request.
#
#   $ pnpm run dev
#   VITE v5.3.4  ready in 38 ms
#
#   ➜  Local:   http://localhost:5173/dist/
#   ➜  Network: use --host to expose
#   ➜  press h + enter to show help
#
ENV RACK_ENV=production

WORKDIR $CODE_ROOT

# Copy the default config file into place if it doesn't
# already exist. If it does exist, nothing happens. For
# example, if the config file has been previously copied
# (and modified) the "--no-clobber" argument prevents
# those changes from being overwritten.
RUN set -eux && \
    cp --preserve --no-clobber etc/defaults/config.defaults.yaml etc/config.yaml && \
    chmod +x bin/entrypoint.sh bin/check-migration-status.sh

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

# Rack app
EXPOSE 3000

CMD ["bin/entrypoint.sh"]
