#!/bin/bash
#
# scripts/setup_stripe_plans.sh
#
# Creates Stripe products from etc/billing/plan-catalog.yaml
#
# Usage:
#   ./scripts/setup_stripe_plans.sh          # Create products (fail if exist)
#   ./scripts/setup_stripe_plans.sh --update # Auto-update existing products
#   ./scripts/setup_stripe_plans.sh --force  # Create duplicates (not recommended)
#
# Prerequisites:
#   - .env file with STRIPE_KEY configured
#   - bin/ots CLI available
#   - etc/billing/plan-catalog.yaml exists
#   - yq command installed (brew install yq)
#

set -e

# Parse command line arguments
UPDATE_MODE=false
FORCE_MODE=false

for arg in "$@"; do
  case $arg in
    --update)
      UPDATE_MODE=true
      shift
      ;;
    --force)
      FORCE_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--update|--force]"
      exit 1
      ;;
  esac
done

# Check for yq
if ! command -v yq &> /dev/null; then
  echo "❌ Error: yq command not found"
  echo "Install with: brew install yq"
  exit 1
fi

# Check for catalog file
CATALOG_FILE="etc/billing/plan-catalog.yaml"
if [ ! -f "$CATALOG_FILE" ]; then
  echo "❌ Error: $CATALOG_FILE not found"
  exit 1
fi

# Load environment variables
if [ -f .env ]; then
  source .env
else
  echo "❌ Error: .env file not found"
  echo "Please create .env with STRIPE_KEY"
  exit 1
fi

# Verify STRIPE_KEY is set
if [ -z "$STRIPE_KEY" ]; then
  echo "❌ Error: STRIPE_KEY not set in .env"
  exit 1
fi

# Determine CLI flags based on mode
CLI_FLAGS="--yes"
if [ "$UPDATE_MODE" = true ]; then
  CLI_FLAGS="--yes --update"
  echo "🔧 Setting up Stripe products (update mode)..."
elif [ "$FORCE_MODE" = true ]; then
  CLI_FLAGS="--yes --force"
  echo "🔧 Setting up Stripe products (force mode - will create duplicates)..."
else
  echo "🔧 Setting up Stripe products (create mode)..."
fi
echo ""

# Extract plan IDs from catalog (excluding free_v1 which has no Stripe product)
PLAN_IDS=$(yq eval '.plans | keys | .[] | select(. != "free_v1")' "$CATALOG_FILE")

# Process each plan
for plan_id in $PLAN_IDS; do
  # Extract plan data from YAML
  name=$(yq eval ".plans.$plan_id.name" "$CATALOG_FILE")
  tier=$(yq eval ".plans.$plan_id.tier" "$CATALOG_FILE")
  region=$(yq eval ".plans.$plan_id.region" "$CATALOG_FILE")
  tenancy=$(yq eval ".plans.$plan_id.tenancy" "$CATALOG_FILE")
  display_order=$(yq eval ".plans.$plan_id.display_order" "$CATALOG_FILE")
  show_on_plans_page=$(yq eval ".plans.$plan_id.show_on_plans_page" "$CATALOG_FILE")

  # Extract capabilities as comma-separated string
  capabilities=$(yq eval ".plans.$plan_id.capabilities | join(\",\")" "$CATALOG_FILE")

  # Extract limits
  limit_teams=$(yq eval ".plans.$plan_id.limits.teams" "$CATALOG_FILE")
  limit_members_per_team=$(yq eval ".plans.$plan_id.limits.members_per_team" "$CATALOG_FILE")
  limit_custom_domains=$(yq eval ".plans.$plan_id.limits.custom_domains" "$CATALOG_FILE")
  limit_secret_lifetime=$(yq eval ".plans.$plan_id.limits.secret_lifetime" "$CATALOG_FILE")
  limit_secrets_per_day=$(yq eval ".plans.$plan_id.limits.secrets_per_day" "$CATALOG_FILE")

  echo "Creating/updating: $name ($plan_id)..."

  # Build command with optional limit fields (only include if not null)
  cmd="bin/ots billing products create \"$name\" $CLI_FLAGS \
    --plan-id $plan_id \
    --tier $tier \
    --region $region \
    --tenancy $tenancy \
    --capabilities $capabilities \
    --display-order $display_order \
    --show-on-plans-page $show_on_plans_page"

  # Add limit fields if they're not null
  [ "$limit_teams" != "null" ] && cmd="$cmd --limit-teams $limit_teams"
  [ "$limit_members_per_team" != "null" ] && cmd="$cmd --limit-members-per-team $limit_members_per_team"
  [ "$limit_custom_domains" != "null" ] && cmd="$cmd --limit-custom-domains $limit_custom_domains"
  [ "$limit_secret_lifetime" != "null" ] && cmd="$cmd --limit-secret-lifetime $limit_secret_lifetime"
  [ "$limit_secrets_per_day" != "null" ] && cmd="$cmd --limit-secrets-per-day $limit_secrets_per_day"

  # Execute command
  eval $cmd

  echo ""
done

echo "✅ All products processed successfully!"
echo ""
echo "Next steps:"
echo "  1. Add prices to products via Stripe Dashboard or:"
echo "     bin/ots billing prices create PRODUCT_ID --amount=2900 --interval=month"
echo "  2. Sync to Redis cache:"
echo "     bin/ots billing sync"
echo "  3. Verify cached plans:"
echo "     bin/ots billing plans"
echo ""
