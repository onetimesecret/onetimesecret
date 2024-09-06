# syntax=docker/dockerfile:1.4

##
# ONETIME SECRET - DOCKER IMAGE - 2024-08-31
#
# To build and use this image, you need to copy the example
# configuration files into place:
#
#     $ cp --preserve --no-clobber ./etc/config.example ./etc/config
#     $ cp --preserve --no-clobber .env.example .env
#
# The default values work as-is but it's a good practice to have
# a look and customize as you like (particularly the main secret
# `SECRET` and redis password in `REDIS_URL`).
#
# USAGE (Docker):
#
# First, start a Redis database with persistence enabled:
#
#     $ docker run -p 6379:6379 --name redis -d redis
#
# Then build and run this image, specifying the redis URL:
#
#     $ docker run -p 3000:3000 -d --name onetimesecret \
#       -e REDIS_URL="redis://172.17.0.2:6379/0" \
#       -e RACK_ENV=production \
#       onetimesecret
#
# It will be accessible on http://localhost:3000.
#
# USAGE (Docker Compose):
#
# When bringing up a frontend container for the first time, make
# sure the database container is already running and attached.
#
#     $ docker-compose up -d redis
#     $ docker-compose up --attach-dependencies --build onetime
#
# If you ever need to force rebuild a container:
#
#     $ docker-compose build --no-cache onetime
#
# ----------------------------------------------------------------
#   NOTE: All Docker Compose configuration (including the service
#         definitions in docker-compose.yml) have moved to a
#         dedicated repo:
#
#         https://github.com/onetimesecret/docker-compose
# ----------------------------------------------------------------
#
# OPTIMIZING BUILDS:
#
# Use `docker history <image_id>` to see the layers of an image.
#
# PRODUCTION DEPLOYMENT:
#
# When deploying to production, you should protect your Redis instance with
# authentication or Redis networks. You should also enable persistence and
# save the data somewhere, to make sure it doesn't get lost when the
# server restarts.
#
# You should also change the secret to something else, and specify the
# domain it will be deployed on. For instance, if OTS will be accessible
# from https://example.com:
#
#   $ docker run -p 3000:3000 -d \
#     -e REDIS_URL="redis://user:password@host:port/0" \
#     -e COLONEL="admin@example.com" \
#     -e HOST=example.com \
#     -e SSL=true \
#     -e SECRET="<put your own secret here>" \
#     -e RACK_ENV=production \
#     onetimesecret
##

##
# BUILDER LAYER
#
# Installs system packages, updates RubyGems, and prepares the
# application's package management dependencies using a Debian
# Ruby 3.3 base image.
#
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/opt/onetime

FROM ruby:3.3-slim-bookworm AS base

# Limit to packages needed for the system itself
ARG PACKAGES="build-essential"

# Fast fail on errors while installing system packages
RUN set -eux \
    && apt-get update \
    && apt-get install -y $PACKAGES \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy Node.js and npm from the official image
COPY --from=node:22 /usr/local/bin/node /usr/local/bin/
COPY --from=node:22 /usr/local/lib/node_modules /usr/local/lib/node_modules

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

# Create the directories that we need in the following image
RUN set -eux \
    && echo "Creating directories" \
    && mkdir -p $CODE_ROOT $ONETIME_HOME/{log,tmp}

WORKDIR $CODE_ROOT

ENV NODE_PATH=$CODE_ROOT/node_modules

# Install the dependencies into the environment image
COPY --link Gemfile Gemfile.lock ./
COPY package.json pnpm-lock.yaml ./

RUN set -eux \
    && bundle config set --local without 'development test' \
    && bundle update --bundler \
    && bundle install \
    && pnpm install --frozen-lockfile

##
# BUILD LAYER
#
FROM app_deps as build
ARG CODE_ROOT

WORKDIR $CODE_ROOT

COPY --link public $CODE_ROOT/public
COPY --link templates $CODE_ROOT/templates
COPY --link src $CODE_ROOT/src
COPY package.json pnpm-lock.yaml tsconfig.json vite.config.ts postcss.config.mjs tailwind.config.ts eslint.config.mjs ./

RUN set -eux \
    && pnpm run type-check \
    && pnpm run build-only \
    && pnpm prune --prod \
    && rm -rf node_modules \
    && npm uninstall -g pnpm  # Remove pnpm after use

##
# APPLICATION LAYER (FINAL)
#
FROM ruby:3.3-slim-bookworm as final
ARG CODE_ROOT

WORKDIR $CODE_ROOT

## Copy only necessary files from previous stages
COPY --link --from=build /usr/local/bundle /usr/local/bundle
COPY --link --from=build $CODE_ROOT/public $CODE_ROOT/public
COPY --link --from=build $CODE_ROOT/templates $CODE_ROOT/templates
COPY --link --from=build $CODE_ROOT/src $CODE_ROOT/src
COPY --link bin $CODE_ROOT/bin
COPY --link etc $CODE_ROOT/etc
COPY --link lib $CODE_ROOT/lib
COPY --link migrate $CODE_ROOT/migrate
COPY VERSION.yml config.ru .commit_hash.txt Gemfile Gemfile.lock $CODE_ROOT/

LABEL Name=onetimesecret Version=0.17.1
LABEL maintainer "Onetime Secret <docker-maint@onetimesecret.com>"
LABEL org.opencontainers.image.description "Onetime Secret is a web application to share sensitive information securely and temporarily. This image contains the application and its dependencies."

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
RUN cp --preserve --no-clobber etc/config.example etc/config

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
