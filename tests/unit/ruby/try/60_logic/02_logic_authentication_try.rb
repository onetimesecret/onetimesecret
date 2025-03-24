# tests/unit/ruby/try/60_logic/02_logic_authentication_try.rb

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
OT.boot! :test, false

# Setup common test variables
@now = DateTime.now
@email = 'test@onetimesecret.com'
@testpass = 'testpass123'
@sess = V2::Session.new '255.255.255.255', 'anon'
@cust = V1::Customer.new @email
@cust.update_passphrase @testpass
@cust.save
@auth_params = {
  u: @email,
  p: @testpass,
  stay: 'true'
}

# AuthenticateSession Tests

## Test authentication with nil customer
@auth = V1::Logic::Authentication::AuthenticateSession.new @sess, nil, {}
[@auth.potential_custid, @auth.custid, @auth.stay]
#=> ['', nil, true]

## Test authentication with valid credentials

@auth = V1::Logic::Authentication::AuthenticateSession.new @sess, nil, @auth_params
[@auth.potential_custid, @auth.custid, @auth.stay]
#=> [@email, @email, true]

## Test authentication with invalid credentials
@auth_params = {
  u: @email,
  p: 'bogus',
}
@auth = V1::Logic::Authentication::AuthenticateSession.new @sess, nil, @auth_params
[@auth.potential_custid, @auth.custid, @auth.stay]
#=> [@email, nil, true]

## Test authentication with remember me option
@auth = V1::Logic::Authentication::AuthenticateSession.new @sess, nil, @auth_params.merge('stay' => 'false')
@auth.stay # currently hardcoded to stay true
#=> true

# ResetPasswordRequest Tests

## Test password reset request
@reset_params = { u: @email }
@reset = V1::Logic::Authentication::ResetPasswordRequest.new @sess, nil, @reset_params
@reset.custid
#=> @email

## Test invalid email handling
@reset_params = { u: 'invalid@email' }
@reset = V1::Logic::Authentication::ResetPasswordRequest.new @sess, nil, @reset_params
@reset.valid_email?(@reset.custid)
#=> false

# ResetPassword Tests

## Test password reset confirmation
@secret = V1::Secret.new
@secret.custid = @email
@secret.save
@reset_params = {
  key: @secret.key,
  v: @secret.verification,
  newp: 'newpass123',
  newp2: 'newpass123'
}
@reset = V1::Logic::Authentication::ResetPassword.new @sess, @cust, @reset_params
[@reset.secret.class, @reset.is_confirmed]
#=> [V1::Secret, true]

# DestroySession Tests

## Test session destruction
@destroy = V1::Logic::Authentication::DestroySession.new @sess, @cust
@destroy.processed_params
#=> {}

# Cleanup test data
@cust.delete!
@secret.delete! if @secret
