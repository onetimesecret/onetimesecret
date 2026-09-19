#!/usr/bin/env bash
# scripts/rhales-schemas-refresh.sh
#
# Keep a checkout's Rhales hydration schemas in step with the bootstrap contract.
#
# public/schemas/*.json is generated from the <schema> sections of the .rue
# templates (src/schemas/contracts/bootstrap.ts) and is gitignored. In
# development, apps/web/core/application.rb mounts
# Rhales::Middleware::SchemaValidator with fail_on_error when
# public/schemas/index.json exists. The generated schemas are closed
# (additionalProperties: false), so a checkout whose schemas predate a contract
# change refuses every page once the server sends a new field.
#
# Runs from `predev`, so starting the dev frontend heals a stale checkout.
#
# Modes (same split as scripts/billing-docs-generate.sh)
# -----------------------------------------------------
# Default (tolerant): always exits 0.
#   - no public/schemas/index.json → skip. The validator is off in this
#     checkout, and generating here would switch it on. Opt in by running
#     `pnpm run schemas:rhales:generate` yourself.
#   - bundle not installed          → skip (frontend-only dev).
#   - generation fails              → LOUD warning, exit 0 so `pnpm dev` runs.
# --strict (or STRICT=1): a generation failure exits 1.
#
# The backend reads a template's schema on the first page it renders and keeps
# it. If a page was requested before this finished, restart the backend.

set -u

STRICT="${STRICT:-0}"
if [ "${1:-}" = "--strict" ]; then
  STRICT=1
fi

SCHEMAS_DIR="./public/schemas"

if [ ! -f "$SCHEMAS_DIR/index.json" ]; then
  echo "[schemas:rhales:refresh] skipped: no $SCHEMAS_DIR/index.json (dev schema validation is off in this checkout)" >&2
  exit 0
fi

if ! command -v bundle >/dev/null 2>&1; then
  echo "[schemas:rhales:refresh] skipped: bundle not installed" >&2
  exit 0
fi

if ! bundle exec rake rhales:schema:generate \
  TEMPLATES_DIR=./apps/web/core/templates OUTPUT_DIR="$SCHEMAS_DIR" >/dev/null; then
  if [ "$STRICT" = "1" ]; then
    cat >&2 <<'MSG'

*** [schemas:rhales:refresh] GENERATION FAILED (strict mode)
*** Fix the underlying error above before retrying.

MSG
    exit 1
  fi

  cat >&2 <<'MSG'

*** [schemas:rhales:refresh] GENERATION FAILED — public/schemas may be stale.
*** A stale schema makes the dev backend answer 500 for every page.
*** Run `pnpm run schemas:rhales:generate` to see the error, or delete
*** public/schemas/*.json to turn dev schema validation off.

MSG
  exit 0
fi

echo "[schemas:rhales:refresh] regenerated $SCHEMAS_DIR" >&2
