# try/unit/models/organization_billing_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/lib/test_support/billing_helpers'

# Organization Billing Feature tests
#
# Tests billing field management on Organization model.

# Arrange: Explicitly disable billing for standalone-mode tests.
# Tests should declare the state they need (AAA pattern) rather than
# depend on config file defaults that can drift.
BillingTestHelpers.disable_billing!

## Ensure feature and billing metadata are loaded
##
## ApplySubscriptionToOrg is required EXPLICITLY because the feature file only
## loads it when billing is enabled, and disable_billing! above turns it off.
## Without it, clear_billing_fields raises NameError on a targeted run and the
## testcases below never evaluate — they only passed by borrowing a sibling
## file's constant in the full `tests/lanes/run unit` batch.
require 'lib/onetime/models/organization/features/with_organization_billing'
require 'onetime/models/organization'
require 'web/billing/metadata'
require 'billing/operations/apply_subscription_to_org'

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
# Starts from 'active' on purpose: subscription_status is already 'canceled'
# after the test above, so asserting 'canceled' from there cannot tell
# "cleared to canceled" apart from "never touched".
@reloaded.subscription_status = 'active'
@reloaded.save
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

## safe_dump exposes active_subscription true for an active subscription
# The workspace UI pre-disables its delete button on this flag; the server
# guard is Onetime::Operations::Org::Delete's :active_subscription refusal.
# (Continuation lines are single-# : a second `##` renames the testcase.)
@org.subscription_status = 'active'
@org.save
@org.safe_dump[:active_subscription]
#=> true

## safe_dump exposes active_subscription true while trialing
@org.subscription_status = 'trialing'
@org.save
@org.safe_dump[:active_subscription]
#=> true

## safe_dump exposes active_subscription true while past_due
# THE REGRESSION this field was fixed for: past_due is delinquent, not gone.
# The server guard (billing_live?) refuses the delete, so the button must be
# pre-disabled or the owner walks the confirm dialog and gets a 4xx.
@org.subscription_status = 'past_due'
@org.save
@org.safe_dump[:active_subscription]
#=> true

## safe_dump exposes active_subscription true while unpaid
@org.subscription_status = 'unpaid'
@org.save
@org.safe_dump[:active_subscription]
#=> true

## safe_dump exposes active_subscription false while paused
# 'paused' is EXCLUDED on purpose: it has never billed and never expires, so
# it needs a payment method attached by hand before anything can charge.
@org.subscription_status = 'paused'
@org.save
@org.safe_dump[:active_subscription]
#=> false

## safe_dump exposes active_subscription false for an abandoned checkout
# 'incomplete' is EXCLUDED on purpose: it never billed and Stripe expires it
# within ~23h, so blocking a delete on it would strand the owner over a
# checkout they walked away from.
@org.subscription_status = 'incomplete'
@org.save
@org.safe_dump[:active_subscription]
#=> false

## safe_dump exposes active_subscription false once canceled
@org.subscription_status = 'canceled'
@org.save
@org.safe_dump[:active_subscription]
#=> false

## safe_dump exposes active_subscription false when never subscribed
@org.subscription_status = nil
@org.save
@org.safe_dump[:active_subscription]
#=> false

## ----------------------------------------------------------------
## paid? and complimentary? canonical method tests
## ----------------------------------------------------------------

## paid? returns true for active subscription with paid plan
@org.subscription_status = 'active'
@org.planid = 'identity_plus_v1'
@org.save
@org.paid?
#=> true

## paid? returns false for canceled subscription
@org.subscription_status = 'canceled'
@org.save
@org.paid?
#=> false

## paid? returns false for active subscription with free plan
@org.subscription_status = 'active'
@org.planid = 'free_v1'
@org.save
@org.paid?
#=> false

## complimentary? returns true when marker is set and subscription active
@org.subscription_status = 'active'
@org.planid = 'identity_plus_v1'
@org.complimentary = 'true'
@org.save
@org.complimentary?
#=> true

## complimentary? returns false when subscription canceled
@org.subscription_status = 'canceled'
@org.save
@org.complimentary?
#=> false

## complimentary? returns false when marker not set
@org.subscription_status = 'active'
@org.complimentary = nil
@org.save
@org.complimentary?
#=> false

## clear_billing_fields clears complimentary marker
@org.complimentary = 'true'
@org.save
@org.clear_billing_fields
@org.complimentary
#=> nil

## Cleanup
@cleanup_result = @org.destroy!
@cleanup_result.success?
#=> true
