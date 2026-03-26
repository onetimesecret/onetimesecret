# try/unit/models/right_to_be_forgotten_try.rb
#
# frozen_string_literal: true

# Tests for RightToBeForgotten#destroy_requested vs #destroy_requested!
#
# The non-bang method (destroy_requested) modifies the customer in memory
# only. The bang method (destroy_requested!) also persists to Redis.
# This distinction prevents accidental persistence during validation or
# preview flows.

require_relative '../../support/test_helpers'

OT.boot! :test, false

@email = generate_unique_test_email("rtbf")
@cust = Onetime::Customer.create!(email: @email)
@cust.role = 'customer'
@cust.save

## destroy_requested changes role in memory
@cust.destroy_requested
@cust.role
#=> 'user_deleted_self'

## destroy_requested does NOT persist role change to Redis
fresh = Onetime::Customer.find(@cust.objid)
fresh.role
#=> 'customer'

## destroy_requested! persists role change to Redis
@cust2_email = generate_unique_test_email("rtbf_bang")
@cust2 = Onetime::Customer.create!(email: @cust2_email)
@cust2.role = 'customer'
@cust2.save
@cust2.destroy_requested!
fresh2 = Onetime::Customer.find(@cust2.objid)
fresh2.role
#=> 'user_deleted_self'

## destroy_requested sets verified to false in memory
@cust3_email = generate_unique_test_email("rtbf_verified")
@cust3 = Onetime::Customer.create!(email: @cust3_email)
@cust3.verified = 'true'
@cust3.save
@cust3.destroy_requested
@cust3.verified
#=> 'false'

## destroy_requested does NOT persist verified change to Redis
fresh3 = Onetime::Customer.find(@cust3.objid)
fresh3.verified
#=> 'true'

# TEARDOWN

@cust.delete! if @cust&.exists?
@cust2.delete! if @cust2&.exists?
@cust3.delete! if @cust3&.exists?
