require_relative 'support/test_logic'
require 'securerandom'

OT.boot! :test, false

## Debug test
@test_email = "oauth_#{SecureRandom.uuid}@example.com"
@env_valid = {
  'rack.session' => {},
  'HTTP_X_TOKEN_SUBJECT' => 'github.com/testuser',
  'HTTP_X_TOKEN_USER_EMAIL' => @test_email,
  'HTTP_X_TOKEN_USER_NAME' => 'Test User',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@strategy = Onetime::Application::AuthStrategies::HeaderAuthStrategy.new
@result = @strategy.authenticate(@env_valid, nil)
@is_failure = @result.is_a?(Otto::Security::Authentication::AuthFailure)
@failure_reason = @is_failure ? @result.failure_reason : nil
[@result.class.name, @is_failure, @failure_reason]
#=> ['Otto::Security::Authentication::AuthFailure', true, String]
