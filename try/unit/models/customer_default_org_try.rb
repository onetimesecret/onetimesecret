# try/unit/models/customer_default_org_try.rb
#
# frozen_string_literal: true

# Tests for Customer.default_org_id field used by CLI add-member command
#
# The default_org_id field stores the customer's preferred default organization,
# allowing customer support to set a specific org as the customer's active
# workspace without modifying the organization's global is_default flag.

require_relative '../../support/test_helpers'

OT.boot! :test, false

@cust = nil
@org = nil

## Setup - create test customer and organization
@cust = Onetime::Customer.create!(email: "test-default-org-#{SecureRandom.hex(4)}@example.com")
@cust.exists?
#=> true

## Customer should have default_org_id field (nil by default)
@cust.default_org_id.nil?
#=> true

## Create organization for testing
@org = Onetime::Organization.create!(
  'Test Default Org',
  @cust,
  @cust.email
)
@org.exists?
#=> true

## Can set default_org_id on customer
@cust.default_org_id = @org.objid
@cust.save
@cust.default_org_id == @org.objid
#=> true

## default_org_id persists after reload
@reloaded = Onetime::Customer.load(@cust.objid)
@reloaded.default_org_id == @org.objid
#=> true

## Can clear default_org_id
@cust.default_org_id = nil
@cust.save
@cust.default_org_id.to_s.empty?
#=> true

## CLEANUP
@cust&.destroy!
@org&.destroy!
true
#=> true
