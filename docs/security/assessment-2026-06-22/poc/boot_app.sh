#!/usr/bin/env bash
# Boots OneTimeSecret locally for dynamic analysis (synthetic data only).
set -uo pipefail
cd /home/user/onetimesecret
export PATH="/opt/rbenv/versions/3.4.9/bin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export RUBYOPT="-E UTF-8"
export SECRET="$(cat /home/user/security-assessment/notes/.test_secret)"
export REDIS_URL="redis://127.0.0.1:6379/0"
# Bridge needed so Familia::VerifiableIdentifier can mint secret ids:
export IDENTIFIER_SECRET="$(ruby -rsecurerandom -e 'print SecureRandom.hex(32)')"
export VERIFIABLE_ID_HMAC_SECRET="$IDENTIFIER_SECRET"
export RACK_ENV="${RACK_ENV:-development}"
export HOST="localhost:3000"
export SSL=false
exec bundle exec puma -p 3000 -e "$RACK_ENV"
