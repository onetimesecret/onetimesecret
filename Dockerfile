# syntax=docker/dockerfile:experimental@sha256:600e5c62eedff338b3f7a0850beb7c05866e0ef27b2d2e8c02aa468e78496ff5

##
# ONETIME SECRET - DOCKER IMAGE - 2024-04-10
#
#
# To build and use this image, you need to copy the example
# configuration files into place:
#
#     $ cp --preserve --no-clobber ./etc/config.example ./etc/config
#
#           - and -
#
#     $ cp --preserve --no-clobber .env.example .env
#
# The default values work as-is but it's a good practice to have
# a look and customize as you like (partcularly the mast secret
# `SECRET` and redis password in `REDIS_URL`).
#
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
#       onetimesecret
#
# It will be accessible on http://localhost:3000.
#
#
# USAGE (Docker Compose):
#
# When bringing up a frontend container for the first time, makes
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
#     -e SSL=true -e HOST=example.com \
#     -e SECRET="<put your own secret here>" \
#     onetimesecret
#


##
# BASE LAYER
#
# Installs system packages, updates RubyGems, and prepares the
# application's package management dependencies using a Debian
# Ruby 3.2 base image.
#
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/opt/onetime

FROM ruby:3.3-slim-bookworm@sha256:bc6372a998e79b5154c8132d1b3e0287dc656249f71f48487a1ecf0d46c9c080 AS builder

# Limit to packages needed for the system itself
# NOTE: We only need the build tools installed if we need
# to compile anything from source during the build.
# TODO: Use psycopg2-binary and remove psycopg2.
ARG PACKAGES="build-essential autoconf m4 sudo"

# Fast fail on errors while installing system packages
RUN set -eux && \
    apt-get update && \
    apt-get install -y $PACKAGES

RUN gem update --system
RUN gem install bundler


##
# ENVIRONMENT LAYER
#
# Sets up the necessary directories, installs additional
# system packages for userland, and installs the application's
# dependencies using the Base Layer as a starting point.
#
FROM builder AS app_env
ARG CODE_ROOT
ARG ONETIME_HOME

# Limit to packages necessary for onetime and operational tasks
ARG PACKAGES="curl netcat-openbsd vim-tiny less redis-tools"

# Fast fail on errors while installing system packages
RUN set -eux && \
    apt-get update && \
    apt-get install -y $PACKAGES

# Create the directories that we need in the following image
RUN echo "Creating directories"
RUN mkdir -p "$CODE_ROOT"
RUN mkdir -p "$ONETIME_HOME/{log,tmp}"

WORKDIR $CODE_ROOT

COPY Gemfile Gemfile.lock ./

# Install the dependencies into the environment image
RUN bundle config set --local without 'development test'
RUN bundle install
RUN bundle update --bundler


##
# APPLICATION LAYER
#
# Contains the entire application context, including the code,
# configuration files, and all other files needed at run-time.
#
FROM app_env
ARG CODE_ROOT

LABEL Name=onetimesecret Version=0.16.0
LABEL maintainer "Onetime Secret <docker-maint@onetimesecret.com>"
LABEL org.opencontainers.image.description "Onetime Secret is a web application to share sensitive information securely and temporarily. This image contains the application and its dependencies."

# See: https://fly.io/docs/rails/cookbooks/deploy/
ENV RUBY_YJIT_ENABLE=1

WORKDIR $CODE_ROOT

COPY . .

# Copy the default config file into place if it doesn't
# already exist. If it does exist, nothing happens. For
# example, if the config file has been previously copied
# (and modified) the "--no-clobber" argument prevents
# those changes from being overwritten.
RUN cp --preserve --no-clobber \
 etc/config.example etc/config

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
