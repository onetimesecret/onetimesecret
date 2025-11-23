#!/bin/bash
#
# scripts/setup_stripe_plans.sh
#
# Creates Stripe products with proper metadata for Onetime Secret billing.
# Products created: Identity Plus, Team Plus, Organization Plus, Organization Max
#
# Usage:
#   ./scripts/setup_stripe_plans.sh          # Interactive mode (prompts if products exist)
#   ./scripts/setup_stripe_plans.sh --update # Auto-update existing products
#   ./scripts/setup_stripe_plans.sh --force  # Create duplicates (not recommended)
#
# Prerequisites:
#   - .env file with STRIPE_KEY configured
#   - bin/ots CLI available
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

echo "🔧 Setting up Stripe test products..."
echo ""

# Identity Plus (Single Team tier)
echo "Creating Identity Plus..."
bin/ots billing products create "Identity Plus" \
  --plan-id identity_plus_v1 \
  --tier single_team \
  --region EU \
  --tenancy multi \
  --capabilities create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage \
  --display-order 10 \
  --show-on-plans-page true \
  --limit-teams 0 \
  --limit-members-per-team 1 \
  --limit-custom-domains -1 \
  --limit-secret-lifetime 2592000 \
  --limit-secrets-per-day -1

echo ""

# Team Plus (Multi Team tier - 1 team)
echo "Creating Team Plus..."
bin/ots billing products create "Team Plus" \
  --plan-id team_plus_v1 \
  --tier multi_team \
  --region EU \
  --tenancy multi \
  --capabilities create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members \
  --display-order 20 \
  --show-on-plans-page true \
  --limit-teams 1 \
  --limit-members-per-team 10 \
  --limit-custom-domains -1 \
  --limit-secret-lifetime 2592000

echo ""

# Organization Plus (Multi Team tier - unlimited teams)
echo "Creating Organization Plus..."
bin/ots billing products create "Organization Plus" \
  --plan-id org_plus_v1 \
  --tier multi_team \
  --region EU \
  --tenancy multi \
  --capabilities create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members,audit_logs,sso \
  --display-order 30 \
  --show-on-plans-page false \
  --limit-teams -1 \
  --limit-members-per-team 25 \
  --limit-custom-domains -1 \
  --limit-secret-lifetime 2592000

echo ""

# Organization Max (Dedicated tier - unlimited everything)
echo "Creating Organization Max..."
bin/ots billing products create "Organization Max" \
  --plan-id org_max_v1 \
  --tier multi_team \
  --region EU \
  --tenancy dedicated \
  --capabilities create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members,audit_logs,sso,priority_support,sla \
  --display-order 40 \
  --show-on-plans-page false \
  --limit-teams -1 \
  --limit-members-per-team -1 \
  --limit-custom-domains -1 \
  --limit-secret-lifetime -1

echo ""
echo "✅ Products created successfully!"
echo ""
echo "Next steps:"
echo "  1. Add prices to products via Stripe Dashboard or CLI"
echo "  2. Run: bin/ots billing sync"
echo "  3. Verify: bin/ots billing plans"
echo ""
