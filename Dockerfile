# syntax=docker/dockerfile:1.15@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
# check=error=true

##
# ONETIME SECRET - DOCKER IMAGE
#
# This Dockerfile defines the build process for the OneTime Secret application.
#
#
# GETTING STARTED:
#
# For comprehensive instructions on building, running, and configuring
# this image, please see our detailed guide:
#
#     docs/DOCKER.md
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
#
# RUNNING:
#
# 1. Start a Valkey/Redis container:
#     $ docker run -d --name valkey -p 6379:6379 valkey/valkey
#
# 2. Set a unique secret:
#     $ openssl rand -hex 24
#    (Copy the output from above command and save it somewhere safe)
#
#     $ echo -n "Enter a secret and press [ENTER]: "; read -s SECRET
#     (Paste the secret you copied from the openssl command above)
#
# 3. Run the application:
#     $ docker run -p 3000:3000 -d --name onetimesecret \
#         -e SECRET=$SECRET \
#         -e REDIS_URL=redis://host.docker.internal:6379/0 \
#         onetimesecret
#
# The app will be at http://localhost:3000. For more, see docs/DOCKER.md.

##
# BASE LAYER
#
# Installs system packages, updates RubyGems, and prepares the
# application's package management dependencies using a Debian
# Ruby 3.4 base image.
#
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/app
ARG VERSION

FROM docker.io/library/ruby:3.4-slim-bookworm@sha256:93664239ae7e485147c2fa83397fdc24bf7b7f1e15c3ad9d48591828a50a50e7 AS base

# Limit to packages needed for the system itself
ARG PACKAGES="build-essential libffi-dev libyaml-dev git"
ARG EXTRA_PACKAGES="curl" # rsync less netcat-openbsd yq

# Fast fail on errors while installing system packages
RUN set -eux \
  && apt-get update \
  && apt-get install -y $PACKAGES

# Install extras if any are specified. This is a helpful placeholder
# that does nothing if EXTRA_PACKAGES is empty. This approach supports
# adding packages without having to install all of the PACKAGES every
# time it changes.
RUN set -eux \
  && test $EXTRA_PACKAGES \
  && apt-get install -y $EXTRA_PACKAGES \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && case "$(uname -m)" in \
    "x86_64") PLATFORM_ARCH="amd64" ;; \
    "aarch64") PLATFORM_ARCH="arm64" ;; \
    *) PLATFORM_ARCH="amd64" ;; \
  esac \
  && curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${PLATFORM_ARCH}" -o /usr/local/bin/yq \
  && chmod +x /usr/local/bin/yq

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
FROM base AS dependencies
ARG CODE_ROOT
ARG ONETIME_HOME
ARG VERSION

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
FROM dependencies AS build
ARG ONETIME_HOME
ARG CODE_ROOT
ARG VERSION

# Create the directories that we need in the following image
RUN set -eux \
  && echo "Creating directories" \
  && mkdir -p $ONETIME_HOME/etc

WORKDIR $CODE_ROOT

COPY public $CODE_ROOT/public
COPY templates $CODE_ROOT/templates
COPY src $CODE_ROOT/src
COPY package.json pnpm-lock.yaml tsconfig.json vite.config.ts postcss.config.mjs tailwind.config.ts eslint.config.ts ./

# Remove pnpm after use
RUN set -eux \
  && pnpm run build \
  && pnpm run schema:generate \
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
FROM ruby:3.4-slim-bookworm@sha256:93664239ae7e485147c2fa83397fdc24bf7b7f1e15c3ad9d48591828a50a50e7 AS final
ARG CODE_ROOT
ARG ONETIME_HOME
ARG VERSION
LABEL org.opencontainers.image.version=$VERSION

WORKDIR $CODE_ROOT

## Copy only necessary files from previous stages
COPY --from=dependencies /usr/local/bin/yq /usr/local/bin/yq
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build $CODE_ROOT/etc/ ./etc/
COPY --from=build $CODE_ROOT/public ./public
COPY --from=build $CODE_ROOT/templates ./templates
COPY --from=build $CODE_ROOT/src ./src
COPY bin ./bin
COPY apps ./apps
COPY lib ./lib
COPY migrate ./migrate
COPY scripts/entrypoint.sh ./bin/
COPY scripts/update-version.sh ./bin/
COPY package.json config.ru Gemfile Gemfile.lock ./

# Copy build stage metadata files
COPY --from=build /tmp/build-meta/commit_hash.txt ./.commit_hash.txt

# Enable Ruby's YJIT compiler for improved performance in Ruby 3.4+
# YJIT is a lightweight, minimalistic Ruby JIT built inside CRuby that
# provides significant performance improvements for most Ruby applications.
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
ENV ONETIME_HOME="$ONETIME_HOME"

WORKDIR $CODE_ROOT

# Copy the default config files into place if the don't
# already exist. If a file does exist, nothing happens. For
# example, if the config file has been previously copied
# (and modified) the "--no-clobber" argument prevents
# those changes from being overwritten.
RUN set -eux \
  && cp --preserve --no-clobber etc/defaults/config.defaults.yaml etc/config.yaml \
  && cp --preserve --no-clobber etc/defaults/mutable.defaults.yaml etc/mutable.yaml

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
