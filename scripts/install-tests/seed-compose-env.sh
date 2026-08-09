#!/usr/bin/env bash
#
# scripts/install-tests/seed-compose-env.sh
#
# Seeds throwaway secrets for the full-stack compose smoke lanes and writes
# both targets compose needs:
#
#   $GITHUB_ENV  — satisfies ${SECRET:?} / ${VALKEY_PASSWORD:?} /
#                  ${RABBITMQ_USER:?} / ${RABBITMQ_PASS:?} interpolation for
#                  every `config`/`build`/`up`, plus AUTH_SECRET /
#                  ACCOUNT_ID_SECRET, which rodauth-tools' hmac_secret_guard
#                  and account_id_obfuscation fail closed on in production
#                  (an unset RACK_ENV counts as production).
#   .env         — the `env_file: ../../.env` target, which must exist at
#                  container runtime. That path resolves to the repo root, so
#                  this script writes there by script location rather than by
#                  cwd (a workflow-level `working-directory:` would otherwise
#                  strand the file where compose can't see it).
#
# Shared by the full-stack-smoke and app-boot-pinned lanes so the two can't
# drift. The stack is torn down after each run, so throwaway values are fine.
#
set -euo pipefail

: "${GITHUB_ENV:?GITHUB_ENV must be set — this helper runs inside GitHub Actions}"

# Repo root regardless of how the script is invoked (matches check-version-pins.sh).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

secret="$(openssl rand -hex 32)"
auth_secret="$(openssl rand -hex 32)"
account_id_secret="$(openssl rand -hex 32)"
valkey_password="$(openssl rand -hex 32)"
rabbitmq_pass="$(openssl rand -hex 16)"

# Interpolation env for every compose invocation in later steps.
{
  echo "SECRET=$secret"
  echo "AUTH_SECRET=$auth_secret"
  echo "ACCOUNT_ID_SECRET=$account_id_secret"
  echo "VALKEY_PASSWORD=$valkey_password"
  echo "RABBITMQ_USER=ots"
  echo "RABBITMQ_PASS=$rabbitmq_pass"
} >> "$GITHUB_ENV"

# env_file: target consumed by the containers at runtime.
{
  echo "SECRET=$secret"
  echo "VALKEY_PASSWORD=$valkey_password"
  echo "RABBITMQ_USER=ots"
  echo "RABBITMQ_PASS=$rabbitmq_pass"
} > .env
