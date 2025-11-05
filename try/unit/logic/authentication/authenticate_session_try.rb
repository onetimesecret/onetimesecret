# try/60_logic/02_logic_authentication_try.rb

# These tests cover the Authentication logic classes which handle
# session management, password resets, and user authentication.
#
# We test:
# 1. Session authentication
# 2. Password reset requests
# 3. Password reset confirmation
# 4. Session destruction

require_relative '../../../support/test_logic'

# Load the app with test configuration
OT.boot! :test, true

# Setup common test variables
@now = Familia.now
@email = "tryouts+#{Familia.now.to_i}@onetimesecret.com"
@session = {}
@strategy_result = MockStrategyResult.new(session: @session, user: nil)
@cust = Customer.create!(email: @email)
@cust.update_passphrase @testpass
@cust.save
@auth_params = {
  login: @email,
  password: @testpass,
  stay: 'true'
}

# AuthenticateSession Tests

## Test authentication with nil customer
@auth = Logic::Authentication::AuthenticateSession.new @strategy_result, {}
[@auth.potential_email_address, @auth.objid, @auth.stay]
#=> ['', nil, true]

## Test authentication with valid credentials
@auth = Logic::Authentication::AuthenticateSession.new @strategy_result, @auth_params
[@auth.potential_email_address, @auth.objid, @auth.stay]
#=> [@cust.email, @cust.objid, true]

## Test authentication with invalid credentials
@auth_params = {
  login: @email,
  password: 'bogus',
}
@auth = Logic::Authentication::AuthenticateSession.new @strategy_result, @auth_params
[@auth.potential_email_address, @auth.objid, @auth.stay]
#=> [@email, nil, true]

## Test authentication with remember me option
@auth = Logic::Authentication::AuthenticateSession.new @strategy_result, @auth_params.merge('stay' => 'false')
@auth.stay # currently hardcoded to stay true
#=> true

# ResetPasswordRequest Tests

## Test password reset request
@reset_params = { login: @email }
@reset = Logic::Authentication::ResetPasswordRequest.new @strategy_result, @reset_params
@reset.objid
#=> @email

## Test invalid email handling
@reset_params = { login: 'invalid@email' }
@reset = Logic::Authentication::ResetPasswordRequest.new @strategy_result, @reset_params
@reset.valid_email?(@reset.objid)
#=> false

# ResetPassword Tests

## Test password reset confirmation
@secret = Secret.new
@secret.objid = @email
@secret.save
@reset_params = {
  key: @secret.identifier,
  v: @secret.verification,
  newpassword: 'newpass123',
  'password-confirm': 'newpass123'
}
@strategy_result_with_cust = MockStrategyResult.new(session: @session, user: @cust)
@reset = Logic::Authentication::ResetPassword.new @strategy_result_with_cust, @reset_params
# NOTE: Most V2 logic is directly subclassed from V1. See note in ResetPassword
# about whether we can drop the V1 prefix inside the apps/api/v1. That would
# allow us to simply use Customer and Ruby will resolve to the nearest class
# (in theory -- it's possible this only works in tests when we're explicitly
# defining ::Customer).
#
# Intentionally V1::Secret here.
[@reset.secret.class, @reset.is_confirmed]
#=> [TestVersion::Secret, true]

# DestroySession Tests

## Test session destruction
@destroy = Logic::Authentication::DestroySession.new @strategy_result_with_cust, {}
@destroy.processed_params
#=> {}

# Cleanup test data
# @cust.delete!
@secret.delete! if @secret
