# try/unit/models/customer_find_by_extid_try.rb
#
# frozen_string_literal: true

# Tests for Customer.find_by_extid vs Customer.load behavior
#
# Issue: In login.rb:154, Customer.load(account[:external_id]) was incorrect
# because `load` expects an objid (internal UUID-based identifier), but
# account[:external_id] contains an extid (external identifier like "ur...").
#
# The fix uses Customer.find_by_extid(account[:external_id]) which correctly
# looks up by the extid index.
#
# This test verifies:
# 1. find_by_extid correctly retrieves a customer by their extid
# 2. load(extid) does NOT work (returns nil because extid is not an objid)
# 3. load(objid) correctly retrieves the customer
#
# Run: bundle exec try try/unit/models/customer_find_by_extid_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test, false

@test_id = SecureRandom.hex(6)
@email = "extid_test_#{@test_id}@example.com"
@cust = Onetime::Customer.create!(email: @email)
@cust.save

# Capture IDs for testing
@extid = @cust.extid  # External ID like "ur9c6g202oqnpvewujyhgjzhtz0"
@objid = @cust.objid  # Internal UUID like "01937b8f-6d8e-7000-9d3a-00017f3e1234"

# TRYOUTS

## Customer has both extid and objid
[@cust.extid, @cust.objid].all? { |id| id.is_a?(String) && !id.empty? }
#=> true

## extid format starts with 'ur' prefix (from external_identifier feature)
@extid.start_with?('ur')
#=> true

## objid format is a UUID (from object_identifier feature)
# UUIDs are 36 chars with hyphens: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
@objid.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
#=> true

## extid and objid are different identifiers
@extid != @objid
#=> true

## find_by_extid correctly retrieves customer using extid
found = Onetime::Customer.find_by_extid(@extid)
found&.custid == @cust.custid
#=> true

## find_by_extid returns same customer instance data
found = Onetime::Customer.find_by_extid(@extid)
found&.email == @cust.email
#=> true

## load with objid correctly retrieves customer
loaded_by_objid = Onetime::Customer.load(@objid)
loaded_by_objid&.custid == @cust.custid
#=> true

## CRITICAL: load with extid returns nil (extid is not a valid objid)
# This is the bug that was fixed in login.rb:154
# Customer.load expects an objid, not an extid
loaded_by_extid = Onetime::Customer.load(@extid)
loaded_by_extid.nil?
#=> true

## CRITICAL: The bug scenario - simulating what login.rb was doing wrong
# account[:external_id] contains extid, not objid
# Using load() with extid fails to find the customer
account_external_id = @extid  # This is what account[:external_id] contains
wrong_lookup = Onetime::Customer.load(account_external_id)
wrong_lookup.nil?
#=> true

## CRITICAL: The fix - using find_by_extid correctly retrieves the customer
account_external_id = @extid  # This is what account[:external_id] contains
correct_lookup = Onetime::Customer.find_by_extid(account_external_id)
correct_lookup&.custid == @cust.custid
#=> true

## find_by_extid returns nil for non-existent extid
Onetime::Customer.find_by_extid("ur_nonexistent_#{@test_id}")
#=> nil

## find_by_extid returns nil for nil input
Onetime::Customer.find_by_extid(nil)
#=> nil

## find_by_extid returns nil for empty string
Onetime::Customer.find_by_extid('')
#=> nil

## load returns nil for non-existent objid
Onetime::Customer.load("00000000-0000-0000-0000-000000000000")
#=> nil

## Both methods are class methods on Customer
[Onetime::Customer.respond_to?(:find_by_extid), Onetime::Customer.respond_to?(:load)]
#=> [true, true]

# TEARDOWN

begin
  @cust.delete! if @cust&.exists?
rescue StandardError
  nil
end
