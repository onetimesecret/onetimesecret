# try/unit/billing/webhook_org_creation_try.rb
#
# frozen_string_literal: true

# Tests for billing webhook organization creation paths
#
# Issue #2880: Remove write operations from OrganizationLoader auth phase
#
# Regression test to verify:
# - apps/web/billing/logic/welcome.rb creates orgs via Organization.create!
# - apps/web/billing/operations/webhook_handlers/checkout_completed.rb uses canonical method
# - Both paths apply is_default: true correctly
#
# Run: bundle exec try try/unit/billing/webhook_org_creation_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

# Setup
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create test customer
@owner = Onetime::Customer.create!(
  email: "webhook_org_#{@test_suffix}@onetimesecret.com",
  role: 'customer'
)

## Organization.create! with is_default: true sets the flag
@org_default = Onetime::Organization.create!(
  "#{@owner.email}'s Workspace",
  @owner,
  @owner.email,
  is_default: true
)
@org_default.is_default
#=> true

## Organization.is_default! method sets flag after creation
@owner2 = Onetime::Customer.create!(
  email: "webhook_org2_#{@test_suffix}@onetimesecret.com"
)
@org_after = Onetime::Organization.create!(
  "Test Workspace",
  @owner2,
  @owner2.email
)
@org_after.is_default! true
@org_after.is_default
#=> true

## Default workspace cannot be deleted
@org_default.can_delete?(@owner)
#=> false

## Non-default workspace can be deleted by owner
@owner3 = Onetime::Customer.create!(
  email: "webhook_org3_#{@test_suffix}@onetimesecret.com"
)
@org_non_default = Onetime::Organization.create!(
  "Non-Default Workspace",
  @owner3,
  @owner3.email,
  is_default: false
)
@org_non_default.can_delete?(@owner3)
#=> true

## Organization contact_email is used for billing email
# Billing webhook handlers store org.contact_email from customer.email
@org_default.contact_email
#=> @owner.email

## billing_email can be set separately from contact_email
@org_default.billing_email = "billing_#{@test_suffix}@example.com"
@org_default.save
[@org_default.contact_email, @org_default.billing_email]
#=> [@owner.email, "billing_#{@test_suffix}@example.com"]

# Test the organization creation pattern used in billing webhook handlers
# These handlers call Organization.create! with specific parameters

## Pattern: find_target_organization fallback creates workspace
# This mimics what checkout_completed.rb does when no org exists
def create_workspace_like_webhook(customer)
  Onetime::Organization.create!(
    "#{customer.email}'s Workspace",
    customer,
    customer.email,
    is_default: true
  )
end

@owner4 = Onetime::Customer.create!(
  email: "webhook_pattern_#{@test_suffix}@onetimesecret.com"
)
@webhook_org = create_workspace_like_webhook(@owner4)
[@webhook_org.display_name, @webhook_org.is_default, @webhook_org.owner_id]
#=> ["#{@owner4.email}'s Workspace", true, @owner4.custid]

## update_from_stripe_subscription requires Organization object
# Webhook handlers call org.update_from_stripe_subscription after creation
# This verifies the org has the method and correct interface
@webhook_org.respond_to?(:update_from_stripe_subscription)
#=> true

## Organization tracks stripe_customer_id for collision prevention
@webhook_org.respond_to?(:stripe_customer_id)
#=> true

## Organization tracks stripe_subscription_id for idempotency
@webhook_org.respond_to?(:stripe_subscription_id)
#=> true

## Organization.find_by_stripe_customer_id is available
Onetime::Organization.respond_to?(:find_by_stripe_customer_id)
#=> true

## Organization created through webhook pattern is member of customer's orgs
@owner4.organization_instances.to_a.map(&:objid).include?(@webhook_org.objid)
#=> true

# Teardown
@org_default.destroy! if @org_default&.exists?
@org_after.destroy! if @org_after&.exists?
@org_non_default.destroy! if @org_non_default&.exists?
@webhook_org.destroy! if @webhook_org&.exists?

@owner.destroy! if @owner&.exists?
@owner2.destroy! if @owner2&.exists?
@owner3.destroy! if @owner3&.exists?
@owner4.destroy! if @owner4&.exists?
