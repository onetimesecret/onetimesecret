# try/unit/logic/secrets/show_secret_try.rb
#
# frozen_string_literal: true

# These tryouts test the ShowSecret logic functionality in the Onetime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a ShowSecret logic with various arguments
# 2. Testing the visibility of different elements based on receipt state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the ShowSecret logic correctly handles different scenarios
# and properly initializes based on the provided arguments.

require_relative '../../../support/test_logic'

OT.boot! :test, false

@email = generate_unique_test_email("show_secret")
@cust = Onetime::Customer.create!(email: @email)

# Define a lambda to create and return a new receipt instance
# Uses Receipt.spawn_pair which properly encrypts content
@create_receipt = lambda {
  receipt, _secret = Onetime::Receipt.spawn_pair(
    @cust.custid,
    3600,
    "This is a secret message"
  )
  receipt
}

# Use the lambda to create a receipt instance
@receipt = @create_receipt.call

# Mock request object
class MockRequest
  attr_reader :env
  def initialize
    @env = {'ots.locale' => 'en'}
  end
end

@sess = MockSession.new
@strategy_result = MockStrategyResult.new(session: @sess, user: @cust)

## Can create a ShowSecret logic with all arguments
params = {}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## success_data returns nil when no secret
params = {}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.success_data
#=> nil

## success_data returns correct structure when secret is viewable
receipt = @create_receipt.call
secret = receipt.load_secret
params = {
  'identifier' => receipt.secret_identifier
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params)
ret = logic.success_data
ret.keys
#=> [:record, :details]

## Has some essential settings
params = {}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
[logic.site['host'], logic.authentication['enabled'], logic.domains_enabled]
#=> ["127.0.0.1:3000", true, false]

## Raises an exception when there's no receipt (no receipt param)
params = {}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no receipt (invalid receipt param)
params = {
  'identifier' => 'bogus'
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no secret
@receipt.load_secret.received!
params = {
  'identifier' => @receipt.secret_identifier
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no viewable secret
receipt = @create_receipt.call
secret = receipt.load_secret
secret.received!
params = {
  'identifier' => receipt.secret_identifier
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Display domain is nil by default (previously called share_domain, that defaulted to site_host)
receipt = @create_receipt.call
params = {
  'identifier' => receipt.secret_identifier
}
this_logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
this_logic.process
this_logic.display_domain
#=> nil

## Sets locale correctly via params
logic = Logic::Secrets::ShowSecret.new(@strategy_result, { 'locale' => 'es' })
logic.locale
#=> 'es'

## Falls back to default locale if not provided
logic = Logic::Secrets::ShowSecret.new(@strategy_result, {})
logic.locale
#=> 'en'

## Asking the logic about whether the secret value is a single line returns nil when no secret
logic = Logic::Secrets::ShowSecret.new(@strategy_result, {})
logic.one_liner
#=> nil

## Cannot determine if secret is a one-liner when the logic.show_secret is false, even if the secret itself is viewable
receipt = @create_receipt.call
params = {
  'identifier' => receipt.secret_identifier
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.raise_concerns
logic.process
[logic.secret.viewable?, logic.show_secret, logic.one_liner, logic.secret.can_decrypt?]
#=> [true, false, nil, true]

## Correctly determines if secret is a one-liner once we've confirmed to
## continue (even though viewable? now reports false b/c logic.process has
## been run successfully and can never be run again -- as far as its concerned
## the secret has been received).
receipt = @create_receipt.call
params = {
  'identifier' => receipt.secret_identifier,
  'continue' => 'true'
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.raise_concerns
logic.process
[logic.secret.viewable?, logic.show_secret, logic.one_liner, logic.secret.can_decrypt?]
#=> [false, true, true, false]

## Correctly determines if secret is a one-liner if the secret is readable
receipt = @create_receipt.call
secret = receipt.load_secret
params = {
  'identifier' => receipt.secret_identifier
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
secret.received!
logic.process
[secret.viewable?, logic.one_liner]
#=> [false, nil]

## Correctly determines if secret is NOT a one-liner (see note above
## about why logic.secret.viewable? reports false after running process).
multiline_content = "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
receipt, _secret = Onetime::Receipt.spawn_pair(@cust.custid, 3600, multiline_content)
params = {
  'identifier' => receipt.secret_identifier,
  'continue' => 'true'
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [false, false]

## Correctly determines display lines for multi-line secrets
multiline_content = "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
receipt, _secret = Onetime::Receipt.spawn_pair(@cust.custid, 3600, multiline_content)
params = {
  'identifier' => receipt.secret_identifier,
  'continue' => 'true'
}
logic = Logic::Secrets::ShowSecret.new(@strategy_result, params, 'en')
logic.process
logic.display_lines
#=> 9

# Teardown
@receipt.destroy!
@cust.destroy!
