# try/unit/models/customer_apitoken_try.rb
#
# frozen_string_literal: true

# These tryouts test the timing-safe apitoken? method on Customer.
#
# The method at Customer#apitoken? (defined in customer.rb) overrides
# the naive string comparison from DeprecatedFields::InstanceMethods
# with Rack::Utils.secure_compare to prevent timing attacks.
#
# Tests cover:
# 1. Returns true when the token matches
# 2. Returns false when the token does not match
# 3. Returns false for nil input
# 4. Returns false for empty string input
# 5. Returns false when the customer has no apitoken set
# 6. Confirms the method uses Rack::Utils.secure_compare (not ==)

require_relative '../../support/test_helpers'

OT.boot! :test, false

@cust = Onetime::Customer.new(email: generate_random_email)
@token = Familia.generate_id
@cust.apitoken = @token

# TRYOUTS

## apitoken? returns true when the token matches
@cust.apitoken?(@token)
#=> true

## apitoken? returns false when the token does not match
@cust.apitoken?('wrong-token-value')
#=> false

## apitoken? returns false for nil input
@cust.apitoken?(nil)
#=> false

## apitoken? returns false for empty string input
@cust.apitoken?('')
#=> false

## apitoken? returns false when the customer has no apitoken set
bare_cust = Onetime::Customer.new(email: generate_random_email)
bare_cust.apitoken?('any-value')
#=> false

## apitoken? returns false when both apitoken and value are empty
bare_cust = Onetime::Customer.new(email: generate_random_email)
bare_cust.apitoken?('')
#=> false

## apitoken? returns false when both apitoken and value are nil
bare_cust = Onetime::Customer.new(email: generate_random_email)
bare_cust.apitoken?(nil)
#=> false

## Customer#apitoken? is defined directly on Customer (not only in the module)
Onetime::Customer.instance_method(:apitoken?).owner
#=> Onetime::Customer

## The direct method uses secure_compare (source includes 'secure_compare')
src = Onetime::Customer.instance_method(:apitoken?).source_location
File.read(src[0]).lines[src[1] - 1, 5].join.include?('secure_compare')
#=> true
