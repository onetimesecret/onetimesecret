require_relative '../support/test_helpers'

# Organization Billing Feature tests
#
# Tests billing field management on Organization model.

## Setup: Ensure feature is loaded
require 'lib/onetime/models/features/with_organization_billing'
require 'onetime/models/organization'

## Create test customer
@cust = Onetime::Customer.create!(
  email: "billing-test-#{SecureRandom.hex(4)}@example.com"
)
@cust.class
#=> Onetime::Customer

## Create test organization
@org = Onetime::Organization.create!(
  'Test Billing Org',
  @cust,
  @cust.email
)
@org.class
#=> Onetime::Organization

## Verify billing fields exist
@org.respond_to?(:stripe_customer_id)
#=> true

## Verify subscription status field
@org.respond_to?(:subscription_status)
#=> true

## Verify plan ID field
@org.respond_to?(:planid)
#=> true

## Set billing fields
@org.stripe_customer_id = 'cus_test123'
@org.stripe_subscription_id = 'sub_test123'
@org.subscription_status = 'active'
@org.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@org.planid = 'single_team_monthly_us_east'
@org.billing_email = 'billing@example.com'
@org.save
#=> true

## Reload and verify
@reloaded = Onetime::Organization.load(@org.orgid)
@reloaded.stripe_customer_id
#=> 'cus_test123'

## Check active subscription
@reloaded.subscription_status = 'active'
@reloaded.save
@reloaded.active_subscription?
#=> true

## Check trialing subscription
@reloaded.subscription_status = 'trialing'
@reloaded.save
@reloaded.active_subscription?
#=> true

## Check past due
@reloaded.subscription_status = 'past_due'
@reloaded.save
@reloaded.past_due?
#=> true

## Check canceled
@reloaded.subscription_status = 'canceled'
@reloaded.save
@reloaded.canceled?
#=> true

## Clear billing fields
@reloaded.clear_billing_fields
@reloaded.subscription_status
#=> 'canceled'

## Verify subscription ID is cleared
@reloaded.stripe_subscription_id
#=> nil

## Cleanup
@cleanup_result = @org.destroy!
@cleanup_result.success?
#=> true
