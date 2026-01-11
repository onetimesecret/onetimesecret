# try/unit/billing/webhook_sync_flag_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/lib/webhook_sync_flag'

# Setup
@test_org_extid = "org_#{SecureRandom.hex(8)}"

## Sets skip-sync flag for organization
Billing::WebhookSyncFlag.set_skip_stripe_sync(@test_org_extid)
Billing::WebhookSyncFlag.skip_stripe_sync?(@test_org_extid)
#=> true

## Returns false when flag not set
unset_org = "org_#{SecureRandom.hex(8)}"
Billing::WebhookSyncFlag.skip_stripe_sync?(unset_org)
#=> false

## Clears skip-sync flag
Billing::WebhookSyncFlag.set_skip_stripe_sync(@test_org_extid)
Billing::WebhookSyncFlag.clear_skip_stripe_sync(@test_org_extid)
Billing::WebhookSyncFlag.skip_stripe_sync?(@test_org_extid)
#=> false

## Flag expires after TTL
# Note: We can't easily test TTL expiration in unit tests
# This test just verifies the constant is set
Billing::WebhookSyncFlag::SKIP_SYNC_TTL
#=> 30

# Teardown
Billing::WebhookSyncFlag.clear_skip_stripe_sync(@test_org_extid)
