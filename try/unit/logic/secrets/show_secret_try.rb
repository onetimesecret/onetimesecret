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
@strategy_result = MockStrategyResult.authenticated(@cust, session: @sess)

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
@receipt.load_secret.revealed!
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
secret.revealed!
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
## the secret has been revealed).
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
secret.revealed!
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

# Anonymous User Tests (verify_owner flow with anonymous_user?)

## anonymous_user? returns true for anonymous strategy result
anon_sess = MockSession.new
anon_strategy = MockStrategyResult.anonymous
logic = Logic::Secrets::ShowSecret.new(anon_strategy, {}, 'en')
logic.anonymous_user?
#=> true

## anonymous_user? returns false for authenticated strategy result
auth_sess = MockSession.new
auth_strategy = MockStrategyResult.authenticated(@cust, session: auth_sess)
logic = Logic::Secrets::ShowSecret.new(auth_strategy, {}, 'en')
logic.anonymous_user?
#=> false

## verify_owner succeeds for anonymous user with verification secret
# Create an unverified owner for verification flow
verify_email = generate_unique_test_email("verify_anon")
@verify_owner = Onetime::Customer.create!(email: verify_email)
@verify_owner.verified = false
@verify_owner.save
# Create a verification secret
verify_receipt, verify_secret = Onetime::Receipt.spawn_pair(@verify_owner.custid, 3600, "verification content")
verify_secret.verification = true
verify_secret.save
# Anonymous user should be able to verify
anon_sess = MockSession.new
anon_strategy = MockStrategyResult.new(session: anon_sess, user: nil, auth_method: 'anonymous')
params = {
  'identifier' => verify_secret.identifier,
  'continue' => 'true'
}
logic = Logic::Secrets::ShowSecret.new(anon_strategy, params, 'en')
logic.process
# Owner should now be verified
@verify_owner.refresh!
[logic.show_secret, @verify_owner.verified?]
#=> [true, true]

## verify_owner fails for different authenticated user
# Create owner and a different authenticated user
owner_email = generate_unique_test_email("verify_owner")
different_email = generate_unique_test_email("different_user")
@owner_cust = Onetime::Customer.create!(email: owner_email)
@owner_cust.verified = false
@owner_cust.save
@different_cust = Onetime::Customer.create!(email: different_email)
@different_cust.verified = true
@different_cust.save
# Create verification secret for owner
owner_receipt, owner_secret = Onetime::Receipt.spawn_pair(@owner_cust.custid, 3600, "owner verification")
owner_secret.verification = true
owner_secret.save
# Different authenticated user tries to verify
diff_sess = MockSession.new
diff_strategy = MockStrategyResult.authenticated(@different_cust, session: diff_sess)
params = {
  'identifier' => owner_secret.identifier,
  'continue' => 'true'
}
logic = Logic::Secrets::ShowSecret.new(diff_strategy, params, 'en')
begin
  logic.process
  false
rescue OT::FormError => e
  e.message.include?("can't verify")
end
#=> true

# Teardown
@receipt.destroy!
@cust.destroy!
@verify_owner&.destroy!
@owner_cust&.destroy!
@different_cust&.destroy!
