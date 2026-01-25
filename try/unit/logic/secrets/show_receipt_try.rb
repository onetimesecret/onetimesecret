# try/unit/logic/secrets/show_receipt_try.rb
#
# frozen_string_literal: true

# These tryouts test the ShowReceipt logic functionality in the Onetime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a ShowReceipt logic with various arguments
# 2. Testing the visibility of different elements based on receipt state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the ShowReceipt logic correctly handles different scenarios
# and properly initializes based on the provided arguments.

require_relative '../../../support/test_logic'

OT.boot! :test, false

@email = generate_unique_test_email("show_receipt")
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

## Can create a ShowReceipt logic with all arguments
params = {}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## Correctly sets basic success_data
params = {}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
res = logic.success_data
res.keys
[:record, :details]
#=> [:record, :details]

## Has some essential settings
params = {}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
[logic.site['host'], logic.authentication['enabled'], logic.domains_enabled]
#=> ["127.0.0.1:3000", true, false]

## Raises an exception when there's no receipt (no receipt param)
params = {}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no receipt (invalid receipt param)
params = {
  key: 'bogus'
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## No exceptions raised when receipt can be loaded
params = {
  'identifier' => @receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.raise_concerns
@receipt.identifier
#=> @receipt.identifier

## Generates correct share URI
params = {
  'identifier' => @receipt.identifier
}
@this_logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
@this_logic.raise_concerns
@this_logic.process
@this_logic.share_url
#=> "#{@this_logic.baseuri}/secret/#{@this_logic.secret.identifier}"

## Share domain in site.host by default
receipt = @create_receipt.call
params = {
  'identifier' => receipt.identifier
}
@this_logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
@this_logic.process
"https://#{@this_logic.site['host']}"
#=> @this_logic.share_domain

## Share domain is still site.host even when the receipt has it set if domains is not enabled
receipt = @create_receipt.call
receipt.share_domain! "example.com"
params = {
  'identifier' => receipt.identifier
}
@this_logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
@this_logic.process
["https://#{@this_logic.site['host']}", @this_logic.domains_enabled]
#=> [@this_logic.share_domain, false]

## Share domain is processed correctly when the receipt has it set and domains is enabled
receipt = @create_receipt.call
receipt.share_domain! "example.com"
params = {
  'identifier' => receipt.identifier
}
@this_logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
@this_logic.instance_variable_set(:@domains_enabled, true)
@this_logic.process
["https://example.com", @this_logic.domains_enabled]
#=> [@this_logic.share_domain, true]

## Sets locale correctly via params
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, { 'locale' => 'es' })
logic.locale
#=> 'es'

## Falls back to default locale if not provided
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, {})
logic.locale
#=> 'en'

## Correctly sets expiration stamp
@receipt.secret_ttl = 3600 * 24 * 2
@receipt.save
params = {
  'identifier' => @receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
logic.natural_expiration
#=> "2 days"

## Knows that the receipt has been previewed b/c process has been called several times already
params = {
  'identifier' => @receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
[logic.receipt.state, logic.show_secret_link]
#=> ["previewed", false]

## Shows secret link when previewed for the first time (i.e. processed)
receipt = @create_receipt.call
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
[logic.receipt.state, logic.show_secret_link]
#=> ["previewed", true]

## Doesn't show secret link when for the second time though
receipt = @create_receipt.call
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
logic.process
[logic.receipt.state, logic.show_secret_link]
#=> ["previewed", false]

## Hides secret link when receipt is in revealed state
receipt = @create_receipt.call
receipt.revealed!
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
[logic.receipt.state, logic.show_secret_link]
#=> ["revealed", false]

## Asking the logic about whether the secret value is a single line returns nil when no secret
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, {}, 'en')
logic.one_liner
#=> nil

## Correctly determines if secret is a one-liner if the secret is readable
receipt = @create_receipt.call
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [true, true]

## Correctly determines if secret is a one-liner if the secret is readable
receipt = @create_receipt.call
secret = receipt.load_secret
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
secret.revealed!
logic.process
[secret.viewable?, logic.one_liner]
#=> [false, nil]

## Correctly determines if secret is NOT a one-liner if the secret is readable
multiline_content = "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
receipt, _secret = Onetime::Receipt.spawn_pair(@cust.custid, 3600, multiline_content)
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [true, false]

## Correctly determines display lines for multi-line secrets
multiline_content = "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
receipt, _secret = Onetime::Receipt.spawn_pair(@cust.custid, 3600, multiline_content)
params = {
  'identifier' => receipt.identifier
}
logic = Logic::Secrets::ShowReceipt.new(@strategy_result, params, 'en')
logic.process
logic.display_lines
#=> 9

# Teardown
@receipt.destroy!
@cust.destroy!
