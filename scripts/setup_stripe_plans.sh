#!/bin/bash
#
# scripts/setup_stripe_plans.sh
#
# Creates Stripe products with proper metadata for Onetime Secret billing.
# Products created: Identity Plus, Team Plus, Organization Plus, Organization Max
#
# Usage:
#   ./scripts/setup_stripe_plans.sh
#
# Prerequisites:
#   - .env file with STRIPE_KEY configured
#   - bin/ots CLI available
#

set -e

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
  --plan-id=identity_v1 \
  --tier=single_team \
  --region=EU \
  --tenancy=multi \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage" \
  --limit-teams=0 \
  --limit-secret-lifetime=2592000

echo ""

# Team Plus (Multi Team tier - 1 team)
echo "Creating Team Plus..."
bin/ots billing products create "Team Plus" \
  --plan-id=team_plus_v1 \
  --tier=multi_team \
  --region=EU \
  --tenancy=multi \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members" \
  --limit-teams=1 \
  --limit-members-per-team=10 \
  --limit-custom-domains=-1 \
  --limit-secret-lifetime=2592000

echo ""

# Organization Plus (Multi Team tier - unlimited teams)
echo "Creating Organization Plus..."
bin/ots billing products create "Organization Plus" \
  --plan-id=org_plus_v1 \
  --tier=multi_team \
  --region=EU \
  --tenancy=multi \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members,audit_logs,sso" \
  --limit-teams=-1 \
  --limit-members-per-team=25 \
  --limit-custom-domains=-1 \
  --limit-secret-lifetime=2592000

echo ""

# Organization Max (Dedicated tier - unlimited everything)
echo "Creating Organization Max..."
bin/ots billing products create "Organization Max" \
  --plan-id=org_max_v1 \
  --tier=multi_team \
  --region=EU \
  --tenancy=dedicated \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members,audit_logs,sso,priority_support,sla" \
  --limit-teams=-1 \
  --limit-members-per-team=-1 \
  --limit-custom-domains=-1 \
  --limit-secret-lifetime=-1

echo ""
echo "✅ Products created successfully!"
echo ""
echo "Next steps:"
echo "  1. Add prices to products via Stripe Dashboard or CLI"
echo "  2. Run: bin/ots billing sync"
echo "  3. Verify: bin/ots billing plans"
echo ""
