# syntax=docker/dockerfile:1.21@sha256:27f9262d43452075f3c410287a2c43f5ef1bf7ec2bb06e8c9eeb1b8d453087bc
# check=error=true

##
# SHARED BASE IMAGE
#
# System dependencies, toolchain, and non-root user setup shared across
# all OTS image variants. This image is built as a Bake target and
# injected into downstream Dockerfiles via build contexts.
#
# Contains:
#   - Ruby 3.4 (slim-bookworm) base
#   - Node.js 22 binaries + npm + pnpm
#   - Build toolchain (build-essential, libssl-dev, etc.)
#   - yq for YAML config migration
#   - Non-root appuser (UID 1001)
#
# NOT intended for direct use — consumed by Bake as:
#   contexts = { base = "target:base" }
#

ARG APP_DIR=/app
ARG RUBY_IMAGE_TAG=3.4-slim-bookworm@sha256:1af92319c7301866eddd99a7d43750d64afa1f2b96d9a4cb45167d759e865a85
ARG NODE_IMAGE_TAG=22@sha256:b501c082306a4f528bc4038cbf2fbb58095d583d0419a259b2114b5ac53d12e9

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
ARG APP_DIR

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
        python3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Install yq (optimized for multi-arch)
# Used for migrating config from v0.22 to v0.23+.
# Pinned to a specific version to prevent breaking changes from upstream.
ARG YQ_VERSION=v4.52.4
RUN set -eux && \
    ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64) YQ_ARCH="amd64" ;; \
        arm64) YQ_ARCH="arm64" ;; \
        *) YQ_ARCH="amd64" ;; \
    esac && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" \
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
    npm install -g pnpm@10 && \
    pnpm --version

# Create non-root user
# IMPORTANT: UID/GID 1001 is also defined in Dockerfile (final and final-s6 stages).
# Those stages start from a fresh ruby:slim image, so they recreate appuser independently.
# Keep all three definitions in sync to avoid permission mismatches on shared volumes.
RUN groupadd -g 1001 appuser && \
    useradd -r -u 1001 -g appuser -d ${APP_DIR} -s /sbin/nologin appuser

WORKDIR ${APP_DIR}
