# syntax=docker/dockerfile:experimental

##
# ONETIME - ONETIME IMAGE - 2022-06-24
# 
# NOTE: Does not need to have file access to any pipeline code.
#
#
# Usage:
#
#   When bringing up a frontend container for the first time, makes
#   sure the database container is already running and attached.
#
#     $ docker-compose up --attach-dependencies --build onetime
#
#   If you ever need to force rebuild a container:
#
#     $ docker-compose build --no-cache onetime
#
#

# Grab this from the docker compose environment (e.g. the dotenv)
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/opt/onetime/app

FROM python:3.8-slim AS builder

# Limit to packages needed for the system itself
# NOTE: We only need the build tools installed if we need
# to compile anything from source during the build.
# TODO: Use psycopg2-binary and remove psycopg2.
ARG PACKAGES="build-essential autoconf m4 curl"

# Limit to packages necessary for onetime and operational tasks
ARG ADDITIONAL_PACKAGES="netcat libpq5 libpq-dev postgresql-client-13 vim-tiny iputils-ping iftop pktstat pcp iptraf"

# Fast fail on errors
RUN set -eux

RUN apt-get update
RUN apt-get install -y $PACKAGES
RUN apt-get install -y $ADDITIONAL_PACKAGES


FROM builder AS container
ARG CODE_ROOT
ARG ONETIME_HOME

# Create the directories that we need in the following image
RUN echo "Creating directories"
RUN mkdir -p $CODE_ROOT $ONETIME_HOME

WORKDIR $CODE_ROOT

# Run the most recent version of pip to avoid its complaints
RUN pip install --upgrade pip

# Use a BuildKit cache for the pip install cache. Avoids
# installing everything each time a package is updated.
# If something seems wrong, make sure this docker
# daemon setting is enabled: `export DOCKER_BUILDKIT=1`.
#
# Run this to clear the cache:
# `$ docker builder prune --filter type=exec.cachemount`
#
COPY requirements.txt .
RUN --mount=type=cache,target=.cache \
  pip install --quiet -r requirements.txt

# Configure the onetime runtime directory
COPY onetime.yaml $ONETIME_HOME

# Include the entire context with the image. This is how
# the container runs in production. In development, if
# the docker-compose also mounts a volume to the same
# location the volume is what is available inside of
# the container once it's up and running.
COPY . .

#
# NOTE: see docker-compose.yaml for this container,
# specifically the `command` setting.
#
