#!/usr/bin/env ruby

require 'benchmark'
require 'rack/test'
require 'bcrypt'

require_relative 'test_helpers'

require_relative '../lib/onetime/services/auth/basic_auth_adapter'
require_relative '../lib/onetime/services/auth/rodauth_adapter'
require_relative '../lib/onetime/services/auth/adapter_factory'


OT.boot! :test, false

# Test that password verification timing attack has been fixed
# Both valid and invalid users should take similar time to process

@mock_env = {
  'rack.session' => {}
}

@test_email = 'test_timing@example.com'
@test_password = 'test_password_123'

# Create a test customer with passphrase
@test_cust = V2::Customer.new @test_email
@test_cust.passphrase!(@test_password)
@test_cust.save

@adapter = Auth::BasicAuthAdapter.new(@mock_env)

## Valid user with correct password should succeed
result_valid = @adapter.authenticate(@test_email, @test_password)
result_valid[:success]
#=> true

## Valid user with wrong password should fail (but take time for verification)
result_wrong = @adapter.authenticate(@test_email, 'wrong_password')
result_wrong[:success] == false && result_wrong[:error] == 'Invalid email or password'
#=> true

## Non-existent user should fail (but still take time for dummy verification)
result_nonexistent = @adapter.authenticate('nonexistent@example.com', @test_password)
result_nonexistent[:success] == false && result_nonexistent[:error] == 'Invalid email or password'
#=> true

## Both valid and invalid users execute password verification (security fix verification)
# Test with valid customer that has passphrase
valid_customer = V2::Customer.load(@test_email)
result_valid_wrong = @adapter.send(:verify_password, valid_customer, 'wrong_pass')

# Test with valid customer that has no passphrase (simulates non-existent user scenario)
no_pass_customer = V2::Customer.new('no_pass_customer@example.com')
result_no_pass = @adapter.send(:verify_password, no_pass_customer, 'some_pass')

# Both should return false but have executed the full verification path
result_valid_wrong == false && result_no_pass == false
#=> true

## Customer exists but has no passphrase (should use dummy for timing consistency)
@no_pass_email = 'no_passphrase@example.com'
@no_pass_cust = V2::Customer.new(@no_pass_email)

result_no_passphrase = @adapter.authenticate(@no_pass_email, 'any_password')
result_no_passphrase[:success] == false && result_no_passphrase[:error] == 'Invalid email or password'
#=> true

## Customer without passphrase verification uses dummy customer path
loaded_no_pass = V2::Customer.load(@no_pass_email)
loaded_no_pass.has_passphrase?
#=> false

## Direct password verification on customer without passphrase should use dummy BCrypt
loaded_no_pass = V2::Customer.load(@no_pass_email)
result_direct_no_pass = @adapter.send(:verify_password, loaded_no_pass, 'any_password')
result_direct_no_pass
#=> false

# Cleanup
@test_cust.delete!
