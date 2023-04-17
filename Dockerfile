# syntax=docker/dockerfile:experimental

##
# ONETIME - DOCKER IMAGE - 2022-07-09
#
# To use this image, you need a Redis database with persistence enabled.
# You can start one with Docker using i.e.:
#
# Usage (Docker Compose):
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
# Usage (Docker):
#
# $ docker run -p 6379:6379 -d redis
#
# Then start this image, specifying the URL of the redis database:
#
# $ docker run -p 3000:3000 -d \
#     -e ONETIMESECRET_REDIS_URL="redis://172.17.0.1:6379/0" \
#     onetimesecret
#
# It will be accessible on http://localhost:3000.
#
# Production deployment
# ---------------------
#
# When deploying to production, you should protect your Redis instance
# with authentication or Redis networks. You should also enable
# persistence and save the data somewhere, to make sure it doesn't get
# lost when the server restarts.
#
# You should also change the secret to something else, and specify the
# domain it will be deployed on.
# For instance, if OTS will be accessible from https://example.com:
#
# $ docker run -p 3000:3000 -d \
#     -e ONETIMESECRET_REDIS_URL="redis://user:password@host:port/0" \
#     -e ONETIMESECRET_SSL=true -e ONETIMESECRET_HOST=example.com \
#     -e ONETIMESECRET_SECRET="<put your own secret here>" \
#     onetimesecret
#

# Grab this from the docker compose environment (e.g. the dotenv)
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/opt/onetime

FROM ruby:2.6-slim AS builder

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

# Instll the entrypoint script
COPY ./bin .


# Using that as a base image, finish the installation
FROM builder AS container
ARG CODE_ROOT
ARG ONETIME_HOME

LABEL Name=onetimesecret Version=0.11.0

# Limit to packages necessary for onetime and operational tasks
ARG PACKAGES="curl netcat vim-tiny less redis-tools iproute2 iputils-ping iftop pktstat pcp iptraf"

# Fast fail on errors while installing system packages
RUN set -eux && \
    apt-get update && \
    apt-get install -y $PACKAGES

# Create the directories that we need in the following image
RUN echo "Creating directories"
RUN mkdir -p "$CODE_ROOT"
RUN mkdir -p "$ONETIME_HOME/{log,tmp}"

WORKDIR $CODE_ROOT

COPY Gemfile ./

# Install the dependencies into the base image
RUN bundle install
RUN bundle update --bundler


# Include the entire context with the image. This is how
# the container runs in production. In development, if
# the docker-compose also mounts a volume to the same
# location the volume is what is available inside of
# the container once it's up and running.
FROM container

WORKDIR $CODE_ROOT

COPY . .

#
# NOTE: see docker-compose.yaml for this container,
# specifically the `command` setting.
#
