# try/unit/models/customer/apitoken_try.rb
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
# 7. regenerate_apitoken stamps last_apitoken_update in the same write as
#    the new key, and bearer_token_watermark reads the later of that and
#    last_password_update (the v3 bearer-token revocation line)

require_relative '../../../support/test_helpers'

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

## bearer_token_watermark is 0 while neither credential change has been stamped
@fresh = Onetime::Customer.new(email: generate_random_email)
@fresh.save
@fresh.bearer_token_watermark
#=> 0

## regenerate_apitoken returns a new key and persists it with last_apitoken_update
@before  = Familia.now.to_i
@new_key = @fresh.regenerate_apitoken
@stored  = Onetime::Customer.load(@fresh.identifier)
[@new_key == @stored.apitoken, @new_key != @token, @stored.last_apitoken_update.to_i >= @before]
#=> [true, true, true]

## bearer_token_watermark follows the API key rotation
@stored.bearer_token_watermark == @stored.last_apitoken_update.to_i
#=> true

## bearer_token_watermark is the later of the two credential changes
@stored.last_password_update!(@stored.last_apitoken_update.to_i + 10)
@stored.bearer_token_watermark
#=> @stored.last_apitoken_update.to_i + 10

## A password change earlier than the rotation leaves the rotation as the line
@stored.last_password_update!(@stored.last_apitoken_update.to_i - 10)
@stored.bearer_token_watermark
#=> @stored.last_apitoken_update.to_i

@fresh.destroy!
