# syntax=docker/dockerfile:1.15@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
# check=error=true

##
# ONETIME SECRET - DOCKER IMAGE
#
# Multi-stage build optimized for production deployment.
# See docs/docker.md for detailed usage instructions.
#
# IMPORTANT: This Dockerfile requires Docker Bake or --build-context for building.
# The "base" build context is injected by docker/bake.hcl — it is
# NOT a stage defined in this file.
#
#   $ docker buildx bake -f docker/bake.hcl main       # main image
#   $ docker buildx bake -f docker/bake.hcl --print    # dry-run
#
# Or with Podman:
#   $ podman build --build-context base=docker-image://... -t onetimesecret .
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
ARG VERSION
ARG RUBY_IMAGE_TAG=3.4-slim-bookworm@sha256:bbc49173621b513e33c4add027747db0c41d540c86492cca66e90814a7518c84

##
# DEPENDENCIES: Install application dependencies
#
# The "base" context is provided by docker/bake.hcl via:
#   contexts = { base = "target:base" }
#
# It contains: Ruby 3.4, Node 22, build toolchain, yq, pnpm, appuser.
# See docker/base.dockerfile for details.
#
FROM base AS dependencies
ARG APP_DIR

RUN set -eux \
  && mkdir -p ${APP_DIR}/{log,tmp}

WORKDIR ${APP_DIR}

ENV NODE_PATH=${APP_DIR}/node_modules

# Install the dependencies
COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-lock.yaml ./

RUN set -eux \
  && bundle config set --local without 'development test' \
  && bundle update --bundler \
  && bundle install

# Put the npm dependencies in a separate layer to avoid
# rebuilding the gems when the package.json is updated.
RUN set -eux \
  && pnpm install --frozen-lockfile

##
# BUILD: Compile and prepare application assets
#
FROM dependencies AS build
ARG APP_DIR
ARG VERSION

WORKDIR ${APP_DIR}

COPY public ${APP_DIR}/public
COPY templates ${APP_DIR}/templates
COPY src ${APP_DIR}/src
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
# FINAL: Production-ready application image
#
FROM docker.io/library/ruby:${RUBY_IMAGE_TAG} AS final
ARG APP_DIR
ARG VERSION
LABEL org.opencontainers.image.version=$VERSION

WORKDIR ${APP_DIR}

# Create non-root user
RUN groupadd -g 1001 appuser && \
    useradd -r -u 1001 -g appuser -d ${APP_DIR} -s /sbin/nologin appuser

## Copy only necessary files from previous stages
COPY --from=dependencies /usr/local/bin/yq /usr/local/bin/yq
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build ${APP_DIR}/public ${APP_DIR}/public
COPY --from=build ${APP_DIR}/templates ${APP_DIR}/templates
COPY --from=build ${APP_DIR}/src ${APP_DIR}/src
COPY bin ${APP_DIR}/bin
COPY apps ${APP_DIR}/apps
COPY etc ${APP_DIR}/etc
COPY lib ${APP_DIR}/lib
COPY docker/entrypoints/entrypoint.sh ./bin/
COPY docker/entrypoints/check-migration-status.sh ./bin/
COPY scripts/update-version.sh ./bin/
COPY migrations ${APP_DIR}/migrations
COPY package.json config.ru Gemfile Gemfile.lock ${APP_DIR}/

# Copy build stage metadata files
COPY --from=build /tmp/build-meta/commit_hash.txt ${APP_DIR}/.commit_hash.txt

# See: https://fly.io/docs/rails/cookbooks/deploy/
ENV RUBY_YJIT_ENABLE=1

# Explicitly setting the Rack environment to production directs
# the application to use the pre-built JS/CSS assets in the
# "public/web/dist" directory. In dev mode, the application
# expects a vite server to be running on port 5173.
ENV RACK_ENV=production

ENV ONETIME_HOME=${APP_DIR}

# Copy the default config file into place if it doesn't
# already exist. If it does exist, nothing happens.
# The "--no-clobber" argument prevents changes from being overwritten.
RUN set -eux && \
    cp --preserve --no-clobber etc/defaults/config.defaults.yaml etc/config.yaml && \
    chmod +x bin/entrypoint.sh bin/check-migration-status.sh

# Run as non-root user
USER appuser

# Rack app
EXPOSE 3000

CMD ["bin/entrypoint.sh"]
