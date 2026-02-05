# try/unit/models/organization_billing_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'

# Organization Billing Feature tests
#
# Tests billing field management on Organization model.

## Ensure feature is loaded
require 'lib/onetime/models/organization/features/with_organization_billing'
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

## Store test suffix for unique email addresses (used throughout tests)
@test_suffix = SecureRandom.hex(4)
@test_suffix.length
#=> 8

## Set billing fields
@test_stripe_customer_id = "cus_test_#{SecureRandom.hex(4)}"
@test_stripe_subscription_id = "sub_test_#{SecureRandom.hex(4)}"
@org.stripe_customer_id = @test_stripe_customer_id
@org.stripe_subscription_id = @test_stripe_subscription_id
@org.subscription_status = 'active'
@org.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@org.planid = 'single_team_monthly_us_east'
@org.billing_email = "billing-#{@test_suffix}@example.com"
@org.save
#=> true

## Reload and verify
@reloaded = Onetime::Organization.load(@org.objid)
@reloaded.stripe_customer_id
#=> @test_stripe_customer_id

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

## ----------------------------------------------------------------
## billing_email unique index tests
## ----------------------------------------------------------------

## find_by_billing_email returns organization when billing_email matches
@org.billing_email = "unique-billing-#{@test_suffix}@example.com"
@org.save
found = Onetime::Organization.find_by_billing_email("unique-billing-#{@test_suffix}@example.com")
found.objid
#=> @org.objid

## find_by_billing_email returns nil for non-existent email
Onetime::Organization.find_by_billing_email("nonexistent-#{@test_suffix}@nowhere.com")
#=> nil

## ----------------------------------------------------------------
## billing_email and contact_email differentiation tests
## ----------------------------------------------------------------

## billing_email and contact_email can have different values
@org.billing_email = "billing-diff-#{@test_suffix}@example.com"
@org.contact_email = "contact-diff-#{@test_suffix}@example.com"
@org.save
@reloaded_diff = Onetime::Organization.load(@org.objid)
[@reloaded_diff.billing_email, @reloaded_diff.contact_email]
#=> ["billing-diff-#{@test_suffix}@example.com", "contact-diff-#{@test_suffix}@example.com"]

## billing_email can be updated independently of contact_email
@org.billing_email = "new-billing-#{@test_suffix}@example.com"
@org.save
@reloaded_new = Onetime::Organization.load(@org.objid)
[@reloaded_new.billing_email, @reloaded_new.contact_email]
#=> ["new-billing-#{@test_suffix}@example.com", "contact-diff-#{@test_suffix}@example.com"]

## contact_email can be updated independently of billing_email
@org.contact_email = "new-contact-#{@test_suffix}@example.com"
@org.save
@reloaded_contact = Onetime::Organization.load(@org.objid)
[@reloaded_contact.billing_email, @reloaded_contact.contact_email]
#=> ["new-billing-#{@test_suffix}@example.com", "new-contact-#{@test_suffix}@example.com"]

## ----------------------------------------------------------------
## safe_dump includes billing_email
## ----------------------------------------------------------------

## safe_dump includes billing_email field
@org.billing_email = "dump-billing-#{@test_suffix}@example.com"
@org.contact_email = "dump-contact-#{@test_suffix}@example.com"
@org.save
dump = @org.safe_dump
[dump[:billing_email], dump[:contact_email]]
#=> ["dump-billing-#{@test_suffix}@example.com", "dump-contact-#{@test_suffix}@example.com"]

## Cleanup
@cleanup_result = @org.destroy!
@cleanup_result.success?
#=> true
