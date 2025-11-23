#!/bin/bash

# scripts/setup_stripe_plans.s

set -e

source .env

echo "🔧 Setting up Stripe test plans..."

# Identity Plus
echo "Creating Identity Plus..."
bin/ots billing products create "Identity Plus" \
  --plan-id=identity_v1_monthly \
  --tier=single_team \
  --region=us-east \
  --tenancy=multi \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_hom
epage" \
  --limit-teams=0 \
  --limit-secret-lifetime=2592000

# Team Plus
echo "Creating Team Plus..."
bin/ots billing products create "Team Plus" \
  --plan-id=team_plus_v1_monthly \
  --tier=multi_team \
  --region=us-east \
  --tenancy=multi \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_hom
epage,manage_teams,manage_members" \
  --limit-teams=1 \
  --limit-members-per-team=10 \
  --limit-custom-domains=-1 \
  --limit-secret-lifetime=2592000

# Organization Plus
echo "Creating Organization Plus..."
bin/ots billing products create "Organization Plus" \
  --plan-id=org_plus_v1_monthly \
  --tier=multi_team \
  --region=us-east \
  --tenancy=multi \
  --capabilities="create_secrets,view_metadata,api_access,custom_domains,extended_default_expiration,custom_branding,branded_hom
epage,manage_teams,manage_members,audit_logs,sso" \
  --limit-teams=-1 \
  --limit-members-per-team=25 \
  --limit-custom-domains=-1 \
  --limit-secret-lifetime=2592000

echo "✅ Products created! Now add prices via Stripe Dashboard or CLI"
echo ""
echo "Next: bin/ots billing sync"
