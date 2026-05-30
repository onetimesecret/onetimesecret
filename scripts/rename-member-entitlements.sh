#!/usr/bin/env bash
# Rename member/role entitlement keys to align with the Organization model.
#
#   members_per_team           -> total_members_per_org
#   owners_per_team            -> role_owners_per_org
#   admins_per_team            -> role_admins_per_org
#   regular_members_per_team   -> role_members_per_org
#
# Also rewrites the matching Stripe metadata keys (`limit_*`) and the
# Ruby constants (`FIELD_LIMIT_*`).
#
# Leaves `teams.max` / `limit_teams` / `FIELD_LIMIT_TEAMS` alone (intentional).
#
# Dry-run: bash scripts/rename-member-entitlements.sh
# Apply:   bash scripts/rename-member-entitlements.sh --apply
#
# Cassettes (apps/web/billing/spec/fixtures/vcr_cassettes/**) are included
# by default so they stay consistent with code. Pass --skip-cassettes to
# leave them for re-recording instead.

set -euo pipefail

cd "$(dirname "$0")/.."

APPLY=false
SKIP_CASSETTES=false
for arg in "$@"; do
  case "$arg" in
    --apply)          APPLY=true ;;
    --skip-cassettes) SKIP_CASSETTES=true ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# Renames in order: longest/most-specific first so later passes don't corrupt
# earlier results. `regular_members_per_team` must run before `members_per_team`.
#
# Each line: "FROM|TO"
RENAMES=(
  # Ruby constants
  "FIELD_LIMIT_REGULAR_MEMBERS_PER_TEAM|FIELD_LIMIT_ROLE_MEMBERS_PER_ORG"
  "FIELD_LIMIT_MEMBERS_PER_TEAM|FIELD_LIMIT_TOTAL_MEMBERS_PER_ORG"
  "FIELD_LIMIT_OWNERS_PER_TEAM|FIELD_LIMIT_ROLE_OWNERS_PER_ORG"
  "FIELD_LIMIT_ADMINS_PER_TEAM|FIELD_LIMIT_ROLE_ADMINS_PER_ORG"

  # Stripe metadata keys
  "limit_regular_members_per_team|limit_role_members_per_org"
  "limit_members_per_team|limit_total_members_per_org"
  "limit_owners_per_team|limit_role_owners_per_org"
  "limit_admins_per_team|limit_role_admins_per_org"

  # YAML / Ruby keys (catalog + runtime)
  "regular_members_per_team|role_members_per_org"
  "members_per_team|total_members_per_org"
  "owners_per_team|role_owners_per_org"
  "admins_per_team|role_admins_per_org"
)

# File scope: project subtree only, by extension.
EXTS='\.(rb|ts|tsx|vue|yaml|yml|md|js)$'

# Build the file list with ripgrep so .gitignore is respected.
# Use a while-read loop rather than `mapfile`/`readarray` (Bash 4+) so the
# script runs under macOS's default Bash 3.2.
CANDIDATES=()
while IFS= read -r line; do
  CANDIDATES+=("$line")
done < <(
  rg --files \
     --hidden \
     --glob '!node_modules' \
     --glob '!.git' \
     --glob '!tmp' \
     --glob '!log' \
     --glob '!coverage' \
     --glob '!public/dist' \
     --glob '!**/*.lock' \
  | grep -E "$EXTS"
)

if $SKIP_CASSETTES; then
  FILTERED=()
  for f in "${CANDIDATES[@]}"; do
    [[ "$f" == *"/vcr_cassettes/"* ]] && continue
    FILTERED+=("$f")
  done
  CANDIDATES=("${FILTERED[@]}")
fi

# First pass: find files that contain ANY of the FROM strings.
PATTERN=''
for r in "${RENAMES[@]}"; do
  FROM="${r%%|*}"
  [[ -n "$PATTERN" ]] && PATTERN="$PATTERN|"
  PATTERN="$PATTERN$FROM"
done

TOUCHED=()
for f in "${CANDIDATES[@]}"; do
  if grep -qE "$PATTERN" "$f"; then
    TOUCHED+=("$f")
  fi
done

if [[ ${#TOUCHED[@]} -eq 0 ]]; then
  echo "No matches found."
  exit 0
fi

# Apply (or report) rewrites.
for f in "${TOUCHED[@]}"; do
  if $APPLY; then
    for r in "${RENAMES[@]}"; do
      FROM="${r%%|*}"
      TO="${r##*|}"
      # Use perl for in-place edits: identical syntax on macOS (BSD) and Linux
      # (GNU), unlike `sed -i` whose backup-extension handling differs.
      # Use | as delimiter since none of the strings contain it.
      perl -pi -e "s|\Q${FROM}\E|${TO}|g" "$f"
    done
    echo "REWROTE: $f"
  else
    echo "WOULD REWRITE: $f"
  fi
done

echo ""
echo "Total files: ${#TOUCHED[@]}"
if ! $APPLY; then
  echo "(dry-run — pass --apply to write changes)"
fi
