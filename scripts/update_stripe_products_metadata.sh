#!/bin/bash
#
# scripts/update_stripe_products_metadata.sh
#
# Updates existing Stripe products with complete metadata.
# This script uses Stripe CLI directly to ensure all metadata is set.
#
# Usage:
#   ./scripts/update_stripe_products_metadata.sh
#
# Prerequisites:
#   - .env file with STRIPE_API_KEY configured
#   - stripe CLI installed (brew install stripe/stripe-cli/stripe)
#

set -e

# Load environment variables
if [ -f .env ]; then
  source .env
else
  echo "❌ Error: .env file not found"
  exit 1
fi

if [ -z "$STRIPE_API_KEY" ]; then
  echo "❌ Error: STRIPE_API_KEY not set in .env"
  exit 1
fi

echo "🔧 Updating Stripe product metadata..."
echo ""
echo "This will update ALL metadata fields for existing products."
echo "Finding products by plan_id..."
echo ""

# Function to update product metadata
update_product() {
  local plan_id=$1
  local product_name=$2
  local tier=$3
  local region=$4
  local tenancy=$5
  local capabilities=$6
  local display_order=$7
  local show_on_plans_page=$8
  local limit_teams=$9
  local limit_members_per_team=${10}
  local limit_custom_domains=${11}
  local limit_secret_lifetime=${12}
  local limit_secrets_per_day=${13}

  echo "Searching for product with plan_id: $plan_id..."

  # Find product ID by plan_id metadata
  product_id=$(stripe products list --limit 100 | \
    jq -r --arg plan_id "$plan_id" '.data[] | select(.metadata.plan_id == $plan_id) | .id' | head -1)

  if [ -z "$product_id" ]; then
    echo "  ⚠️  Product not found with plan_id: $plan_id"
    echo "  Creating new product instead..."

    stripe products create \
      --name="$product_name" \
      --metadata[app]=onetimesecret \
      --metadata[plan_id]="$plan_id" \
      --metadata[tier]="$tier" \
      --metadata[region]="$region" \
      --metadata[tenancy]="$tenancy" \
      --metadata[capabilities]="$capabilities" \
      --metadata[display_order]="$display_order" \
      --metadata[show_on_plans_page]="$show_on_plans_page" \
      --metadata[limit_teams]="$limit_teams" \
      --metadata[limit_members_per_team]="$limit_members_per_team" \
      --metadata[limit_custom_domains]="$limit_custom_domains" \
      --metadata[limit_secret_lifetime]="$limit_secret_lifetime" \
      --metadata[limit_secrets_per_day]="$limit_secrets_per_day" \
      --metadata[created]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    echo "  ✅ Created product: $product_name"
  else
    echo "  Found product: $product_id"
    echo "  Updating metadata..."

    stripe products update "$product_id" \
      --name="$product_name" \
      --metadata[app]=onetimesecret \
      --metadata[plan_id]="$plan_id" \
      --metadata[tier]="$tier" \
      --metadata[region]="$region" \
      --metadata[tenancy]="$tenancy" \
      --metadata[capabilities]="$capabilities" \
      --metadata[display_order]="$display_order" \
      --metadata[show_on_plans_page]="$show_on_plans_page" \
      --metadata[limit_teams]="$limit_teams" \
      --metadata[limit_members_per_team]="$limit_members_per_team" \
      --metadata[limit_custom_domains]="$limit_custom_domains" \
      --metadata[limit_secret_lifetime]="$limit_secret_lifetime" \
      --metadata[limit_secrets_per_day]="$limit_secrets_per_day"

    echo "  ✅ Updated product: $product_name ($product_id)"
  fi
  echo ""
}

# Update all products
update_product \
  "identity_plus_v1" \
  "Identity Plus" \
  "single_team" \
  "EU" \
  "multi" \
  "create_secrets,view_receipt,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage" \
  "10" \
  "true" \
  "0" \
  "1" \
  "-1" \
  "2592000" \
  "-1"

update_product \
  "team_plus_v1" \
  "Team Plus" \
  "multi_team" \
  "EU" \
  "multi" \
  "create_secrets,view_receipt,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members" \
  "20" \
  "true" \
  "1" \
  "10" \
  "-1" \
  "2592000" \
  "-1"

update_product \
  "org_plus_v1" \
  "Organization Plus" \
  "multi_team" \
  "EU" \
  "multi" \
  "create_secrets,view_receipt,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members,audit_logs,sso" \
  "30" \
  "false" \
  "-1" \
  "25" \
  "-1" \
  "2592000" \
  "-1"

update_product \
  "org_max_v1" \
  "Organization Max" \
  "multi_team" \
  "EU" \
  "dedicated" \
  "create_secrets,view_receipt,api_access,custom_domains,extended_default_expiration,custom_branding,branded_homepage,manage_teams,manage_members,audit_logs,sso,priority_support,sla" \
  "40" \
  "false" \
  "-1" \
  "-1" \
  "-1" \
  "-1" \
  "-1"

echo "✅ All products updated!"
echo ""
echo "Next steps:"
echo "  1. Run: bin/ots billing sync"
echo "  2. Verify: bin/ots billing plans"
echo ""
