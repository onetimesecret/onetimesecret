# try/unit/auth_strategies/header_auth_strategy_try.rb
#
# Tests for HeaderAuthStrategy (OAuth Gateway via Caddy Security)
#
# This strategy authenticates users via X-Token-* headers injected by
# Caddy Security after successful OAuth authentication.

require_relative '../../support/test_logic'
require 'securerandom'

# Load the app with test configuration
OT.boot! :test, false

## Test 1: Missing required headers returns failure
@env_no_headers = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@strategy = Onetime::Application::AuthStrategies::HeaderAuthStrategy.new
@result_missing = @strategy.authenticate(@env_no_headers, nil)
[
  @result_missing.is_a?(Otto::Security::Authentication::AuthFailure),
  @result_missing.authenticated?,
  @result_missing.failure_reason.include?('HEADER_MISSING')
]
#=> [true, false, true]

## Test 2: Missing email header returns failure
@env_no_email = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'github.com/testuser',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_no_email = @strategy.authenticate(@env_no_email, nil)
[
  @result_no_email.is_a?(Otto::Security::Authentication::AuthFailure),
  @result_no_email.authenticated?,
  @result_no_email.failure_reason.include?('EMAIL_MISSING')
]
#=> [true, false, true]

## Test 3: Valid headers create new customer
@test_email = "oauth_#{SecureRandom.uuid}@example.com"
@env_valid = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'github.com/testuser',
  'HTTP_X_TOKEN_USER_EMAIL' => @test_email,
  'HTTP_X_TOKEN_USER_NAME' => 'Test User',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_new = @strategy.authenticate(@env_valid, nil)
[
  @result_new.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_new.authenticated?,
  @result_new.user.class.name,
  @result_new.user.email == @test_email,
  @result_new.auth_method,
  @result_new.metadata[:provider]
]
#=> [true, true, 'Onetime::Customer', true, 'oauth_gateway', 'github.com']

## Test 4: Existing customer is found by email
@existing_email = "existing_#{SecureRandom.uuid}@example.com"
@existing_cust = Onetime::Customer.new(email: @existing_email)
@existing_cust.save
@existing_custid = @existing_cust.custid

@env_existing = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'google.com/existinguser',
  'HTTP_X_TOKEN_USER_EMAIL' => @existing_email,
  'HTTP_X_TOKEN_USER_NAME' => 'Existing User',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_existing = @strategy.authenticate(@env_existing, nil)
[
  @result_existing.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_existing.user.custid == @existing_custid,
  @result_existing.metadata[:provider]
]
#=> [true, true, 'google.com']

## Test 5: Provider extraction from subject works correctly
@providers_test = [
  ['github.com/username', 'github.com'],
  ['google.com/org/username', 'google.com'],
  ['gitlab.com/team/project/user', 'gitlab.com'],
  ['example.com', 'example.com']
]
@provider_results = @providers_test.map do |(subject, expected)|
  env = {
    'rack.session' => {},
    'HTTP_X_TOKEN_SUBJECT' => subject,
    'HTTP_X_TOKEN_USER_EMAIL' => "test_#{SecureRandom.uuid}@example.com",
    'REMOTE_ADDR' => '127.0.0.1'
  }
  result = @strategy.authenticate(env, nil)
  result.metadata[:provider] == expected
end
@provider_results.all?
#=> true

## Test 6: OAuth metadata is properly set
@metadata_email = "metadata_#{SecureRandom.uuid}@example.com"
@env_metadata = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'gitlab.com/metauser',
  'HTTP_X_TOKEN_USER_EMAIL' => @metadata_email,
  'HTTP_X_TOKEN_USER_NAME' => 'Meta User',
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_USER_AGENT' => 'Mozilla/5.0'
}
@result_metadata = @strategy.authenticate(@env_metadata, nil)
[
  @result_metadata.metadata[:provider],
  @result_metadata.metadata[:oauth_subject],
  @result_metadata.metadata[:oauth_email] == @metadata_email,
  @result_metadata.metadata[:ip],
  @result_metadata.metadata[:user_agent]
]
#=> ['gitlab.com', 'gitlab.com/metauser', true, '192.168.1.1', 'Mozilla/5.0']

## Test 7: Strategy returns StrategyResult (never raises)
@bad_env = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'test.com/user',
  'HTTP_X_TOKEN_USER_EMAIL' => 'invalid-email-format'  # Might cause validation issues
}
@result_bad = @strategy.authenticate(@bad_env, nil)
@result_bad.is_a?(Otto::Security::Authentication::StrategyResult)
#=> true

## Test 8: Name is optional, customer created without it
@no_name_email = "no_name_#{SecureRandom.uuid}@example.com"
@env_no_name = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'github.com/noname',
  'HTTP_X_TOKEN_USER_EMAIL' => @no_name_email,
  'REMOTE_ADDR' => '127.0.0.1'
}
@result_no_name = @strategy.authenticate(@env_no_name, nil)
[
  @result_no_name.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_no_name.user.email == @no_name_email
]
#=> [true, true]
