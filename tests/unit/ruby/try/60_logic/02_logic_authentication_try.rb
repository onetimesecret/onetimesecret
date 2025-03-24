# frozen_string_literal: true

# These tests cover the Authentication logic classes which handle
# session management, password resets, and user authentication.
#
# We test:
# 1. Session authentication
# 2. Password reset requests
# 3. Password reset confirmation
# 4. Session destruction

require_relative '../test_helpers'

# Load the app with test configuration
OT.boot! :test

# Setup common test variables
@now = DateTime.now
@email = 'test@onetimesecret.com'
@testpass = 'testpass123'
@sess = OT::Session.new '255.255.255.255', 'anon'
@cust = OT::Customer.new @email
@cust.update_passphrase @testpass
@cust.save
@auth_params = {
  u: @email,
  p: @testpass,
  stay: 'true'
}

# AuthenticateSession Tests

## Test authentication with nil customer
@auth = OT::Logic::Authentication::AuthenticateSession.new @sess, nil, {}
[@auth.potential_custid, @auth.custid, @auth.stay]
#=> ['', nil, true]

## Test authentication with valid credentials

@auth = OT::Logic::Authentication::AuthenticateSession.new @sess, nil, @auth_params
[@auth.potential_custid, @auth.custid, @auth.stay]
#=> [@email, @email, true]

## Test authentication with invalid credentials
@auth_params = {
  u: @email,
  p: 'bogus',
}
@auth = OT::Logic::Authentication::AuthenticateSession.new @sess, nil, @auth_params
[@auth.potential_custid, @auth.custid, @auth.stay]
#=> [@email, nil, true]

## Test authentication with remember me option
@auth = OT::Logic::Authentication::AuthenticateSession.new @sess, nil, @auth_params.merge('stay' => 'false')
@auth.stay # currently hardcoded to stay true
#=> true

# ResetPasswordRequest Tests

## Test password reset request
@reset_params = { u: @email }
@reset = OT::Logic::Authentication::ResetPasswordRequest.new @sess, nil, @reset_params
@reset.custid
#=> @email

## Test invalid email handling
@reset_params = { u: 'invalid@email' }
@reset = OT::Logic::Authentication::ResetPasswordRequest.new @sess, nil, @reset_params
@reset.valid_email?(@reset.custid)
#=> false

# ResetPassword Tests

## Test password reset confirmation
@secret = OT::Secret.new
@secret.custid = @email
@secret.save
@reset_params = {
  key: @secret.key,
  v: @secret.verification,
  newp: 'newpass123',
  newp2: 'newpass123'
}
@reset = OT::Logic::Authentication::ResetPassword.new @sess, @cust, @reset_params
[@reset.secret.class, @reset.is_confirmed]
#=> [OT::Secret, true]

# DestroySession Tests

## Test session destruction
@destroy = OT::Logic::Authentication::DestroySession.new @sess, @cust
@destroy.processed_params
#=> {}

# Cleanup test data
@cust.delete!
@secret.delete! if @secret
