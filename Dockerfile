# syntax=docker/dockerfile:1.15@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
# check=error=true

##
# ONETIME SECRET - DOCKER IMAGE - 2025-05-15
#
# For detailed instructions on building, running, and deploying this Docker image,
# please refer to our comprehensive Docker guide:
#
#     docs/DOCKER.md
#
# This guide includes information on:
# - Quick start instructions
# - Configuration options
# - Production deployment considerations
# - Updating the Docker image
# - Using specific version tags
#
# For more detailed configuration options, you can also refer to the README.md file.
#
# GETTING STARTED:
#
# To build and use this image, you need to copy the example
# configuration files into place:
#
#     $ cp --preserve --no-clobber ./etc/config.example.yaml ./etc/config
#     $ cp --preserve --no-clobber .env.example .env
#
# The default values work as-is but it's a good practice to have
# a look and customize as you like (particularly the main secret
# `SECRET` and redis password in `REDIS_URL`).
#
# BUILDING:
#
#     $ docker build -t onetimesecret .
#
# For multi-platform builds:
#
#     $ docker buildx build --platform=linux/amd64,linux/arm64 . -t onetimesecret
#
# RUNNING:
#
# First, start a Redis server (version 5+) with persistence enabled:
#
#     $ docker run -p 6379:6379 -d redis:bookworm
#
# Then set essential environment variables:
#
#     $ export HOST=localhost:3000
#     $ export SSL=false
#     $ export SECRET=MUST_BE_UNIQUE
#     $ export REDIS_URL=redis://host.docker.internal:6379/0
#     $ export RACK_ENV=production
#
# Run the OnetimeSecret container:
#
#     $ docker run -p 3000:3000 -d --name onetimesecret \
#       -e REDIS_URL=$REDIS_URL \
#       -e SECRET=$SECRET \
#       -e HOST=$HOST \
#       -e SSL=$SSL \
#       -e RACK_ENV=$RACK_ENV \
#       onetimesecret
#
# It will be accessible on http://localhost:3000.
#
# PRODUCTION DEPLOYMENT:
#
# When deploying to production, protect your Redis instance with
# authentication and enable persistence. Also, change the secret and
# specify the domain it will be deployed on. For example:
#
#   $ openssl rand -hex 32
#   [copy value to set SECRET]
#   $ export HOST=example.com
#   $ export SSL=true
#   $ export SECRET=COPIED_VALUE
#   $ export REDIS_URL=redis://username:password@hostname:6379/0
#   $ export RACK_ENV=production
#
#   $ docker run -p 3000:3000 -d --name onetimesecret \
#     -e REDIS_URL=$REDIS_URL \
#     -e SECRET=$SECRET \
#     -e HOST=$HOST \
#     -e SSL=$SSL \
#     -e RACK_ENV=$RACK_ENV \
#     onetimesecret
#
# For more detailed configuration options, refer to the README.md file.

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

FROM docker.io/library/ruby:3.4-slim-bookworm@sha256:f7e6d4dbfbc3198bcb1a060e1d8de0e59443fa88d1a573428b30d174bf3bc837 AS base

# Limit to packages needed for the system itself
ARG PACKAGES="build-essential rsync netcat-openbsd libffi-dev libyaml-dev git"

# Fast fail on errors while installing system packages
RUN set -eux \
  && apt-get update \
  && apt-get install -y $PACKAGES \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Copy Node.js and npm from the official image
COPY --from=docker.io/library/node:22@sha256:0b5b940c21ab03353de9042f9166c75bcfc53c4cd0508c7fd88576646adbf875 /usr/local/bin/node /usr/local/bin/
COPY --from=docker.io/library/node:22@sha256:0b5b940c21ab03353de9042f9166c75bcfc53c4cd0508c7fd88576646adbf875 /usr/local/lib/node_modules /usr/local/lib/node_modules

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
FROM ruby:3.4-slim-bookworm@sha256:f7e6d4dbfbc3198bcb1a060e1d8de0e59443fa88d1a573428b30d174bf3bc837 AS final
ARG CODE_ROOT
ARG VERSION
LABEL org.opencontainers.image.version=$VERSION

WORKDIR $CODE_ROOT

## Copy only necessary files from previous stages
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build $CODE_ROOT/public $CODE_ROOT/public
COPY --from=build $CODE_ROOT/templates $CODE_ROOT/templates
COPY --from=build $CODE_ROOT/src $CODE_ROOT/src
COPY bin $CODE_ROOT/bin
COPY apps $CODE_ROOT/apps
COPY etc $CODE_ROOT/etc
COPY lib $CODE_ROOT/lib
COPY migrate $CODE_ROOT/migrate
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
RUN set -eux \
  && cp --preserve --no-clobber etc/config.example.yaml etc/config.yaml

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
