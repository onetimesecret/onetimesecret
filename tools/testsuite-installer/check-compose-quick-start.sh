#!/usr/bin/env bash

set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/docker/compose"
cp .env.example docker-compose.yml "$work/"
cp docker/compose/docker-compose.simple.yml "$work/docker/compose/"
awk '
  /^## Quick Start$/ { section = 1; next }
  section && /^## / { exit }
  section && /^```bash$/ { block = 1; next }
  block && /^```$/ { exit }
  block { print }
' docker/README.md > "$work/quick-start.sh"
test -s "$work/quick-start.sh"
cd "$work"
unset SECRET VALKEY_PASSWORD COMPOSE_FILE COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE

# Validate the actual Compose config in place of starting services.
docker() {
  case "$*" in
    'compose up')
      command docker compose config --quiet && printf 'checked\n' >> compose-checks
      ;;
    'compose -f - config --images') command docker "$@" ;;
    *) echo 'Unexpected Docker command in the Compose quick start' >&2; return 1 ;;
  esac
}
export -f docker

echo 'Checking fresh setup and rerun'
bash -e quick-start.sh
grep -Eq '^SECRET=[0-9a-f]{64}$' .env
grep -Eq '^VALKEY_PASSWORD=[0-9a-f]{64}$' .env
cp .env first.env
bash -e quick-start.sh
cmp first.env .env
[[ $(wc -l < compose-checks) -eq 2 ]]

echo 'Checking empty shell overrides and a multiline dotenv value'
cat > .env <<'ENV'
SECRET=existing-secret
SAMPLE='multiline value
VALKEY_PASSWORD=example'
ENV
SECRET='' VALKEY_PASSWORD='' bash -e quick-start.sh
[[ $(grep -c '^SECRET=' .env) -eq 1 ]]
grep -qx 'SECRET=existing-secret' .env
grep -Eq '^VALKEY_PASSWORD=[0-9a-f]{64}$' .env

echo 'Checking keys configured in a different project directory'
printf '%s\n' 'COMPOSE_FILE=docker/compose/docker-compose.simple.yml' > .env
printf '%s\n' 'SECRET=project-secret' 'VALKEY_PASSWORD=project-valkey' > docker/compose/.env
cp .env before.env
cp docker/compose/.env project-before.env
bash -e quick-start.sh
cmp before.env .env
cmp project-before.env docker/compose/.env
[[ $(wc -l < compose-checks) -eq 4 ]]

echo 'Checking keys configured by the included stack'
printf '%s\n' 'HOST=localhost:3000' > .env
cp .env before.env
bash -e quick-start.sh
cmp before.env .env
cmp project-before.env docker/compose/.env
[[ $(wc -l < compose-checks) -eq 5 ]]

echo 'Checking a fresh setup with a custom Compose env file'
rm .env docker/compose/.env
printf '%s\n' 'SECRET=custom-secret' 'VALKEY_PASSWORD=custom-valkey' > custom.env
cp custom.env custom-before.env
COMPOSE_ENV_FILES=custom.env bash -e quick-start.sh
test -f .env
test ! -s .env
cmp custom-before.env custom.env
[[ $(wc -l < compose-checks) -eq 6 ]]
