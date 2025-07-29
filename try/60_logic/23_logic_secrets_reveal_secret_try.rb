# try/60_logic/23_logic_secrets_reveal_secret_try.rb

# These tryouts test the RevealSecret logic functionality in the Onetime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a RevealSecret logic with various arguments
# 2. Testing the visibility of different elements based on metadata state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the RevealSecret logic correctly handles different scenarios
# and properly initializes based on the provided arguments.

require_relative '../test_logic'

# Use the default config file for tests
OT.boot! :test, false

@email = "tryouts+#{Time.now.to_i}@onetimesecret.com"
@cust = V2::Customer.create @email

# Define a lambda to create and return a new metadata instance
@create_metadata = lambda {
  metadata = V2::Metadata.create
  secret = V2::Secret.create(value: "This is a secret message")
  metadata.secret_key = secret.key
  metadata.save
  metadata
}

# Use the lambda to create a metadata instance
@metadata = @create_metadata.call

# Mock request object
class MockRequest
  attr_reader :env
  def initialize
    @env = {'ots.locale' => 'en'}
  end
end

# Mock session object
class MockSession
  def authenticated?
    true
  end
  def short_identifier
    "mock_short_identifier"
  end
  def ipaddress
    "mock_ipaddress"
  end
  def add_shrimp
    "mock_shrimp"
  end
  def get_error_messages
    []
  end
  def get_info_messages
    []
  end
  def get_form_fields!
    {}
  end
  def event_incr!(event)
    "mock_event: #{event}"
  end
end

@sess = MockSession.new

## Can create a RevealSecret logic with all arguments
params = {}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## success_data returns nil when no secret
params = {}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.success_data
#=> nil

## success_data returns correct structure when secret is viewable
metadata = @create_metadata.call
secret = metadata.load_secret
params = {
  key: metadata.secret_key
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
ret = logic.success_data
ret.keys
#=> [:record, :details]

## Has some essential settings
params = {}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
[logic.site[:host], logic.authentication[:enabled], logic.domains_enabled]
#=> ["127.0.0.1:3000", true, false]

## Raises an exception when there's no metadata (no metadata param)
params = {}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no metadata (invalid metadata param)
params = {
  key: 'bogus'
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no secret
params = {
  key: @metadata.key
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Raises an exception when there's no viewable secret
metadata = @create_metadata.call
secret = metadata.load_secret
secret.received!
params = {
  key: metadata.secret_key
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## Share domain is site.host by default (same as metadata)
metadata = @create_metadata.call
params = {
  key: metadata.secret_key
}
@this_logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
@this_logic.process
@this_logic.share_domain
#=> "https://127.0.0.1:3000"

## Share domain is still site.host even when the secret has it set if domains is disabled
metadata = @create_metadata.call
secret = metadata.load_secret
secret.share_domain! "example.com"
params = {
  key: metadata.secret_key
}
@this_logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
@this_logic.process
[@this_logic.share_domain, @this_logic.domains_enabled]
#=> ["https://127.0.0.1:3000", false]

## Share domain is processed correctly when the secret has it set
metadata = @create_metadata.call
secret = metadata.load_secret
secret.share_domain! "example.com"
params = {
  key: metadata.secret_key
}
@this_logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
@this_logic.instance_variable_set(:@domains_enabled, true)
@this_logic.process
[@this_logic.share_domain, @this_logic.domains_enabled]
#=> ["https://example.com", true]

## Sets locale correctly
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, {}, 'es')
logic.locale
#=> 'es'

## Falls back to nil locale if not provided
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, {}, nil)
logic.locale
#=> nil

## Asking the logic about whether the secret value is a single line returns nil when no secret
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, {}, 'en')
logic.one_liner
#=> nil

## Cannot determine if secret is a one-liner when the logic.show_secret is false, even if the secret itself is viewable
metadata = @create_metadata.call
params = {
  key: metadata.secret_key
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
[logic.secret.viewable?, logic.show_secret, logic.one_liner, logic.secret.can_decrypt?]
#=> [true, false, nil, true]

## Correctly determines if secret is a one-liner once we've confirmed to
## continue (even though viewable? now reports false b/c logic.process has
## been run successfully and can never be run again -- as far as its concerned
## the secret has been received).
metadata = @create_metadata.call
params = {
  key: metadata.secret_key,
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
[logic.secret.viewable?, logic.show_secret, logic.one_liner, logic.secret.can_decrypt?]
#=> [false, true, true, false]

## Correctly determines if secret is a one-liner if the secret is readable
metadata = @create_metadata.call
secret = metadata.load_secret
params = {
  key: metadata.secret_key
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
secret.received!
logic.process
[secret.viewable?, logic.one_liner]
#=> [false, nil]

## Correctly determines if secret is NOT a one-liner (see note above
## about why logic.secret.viewable? reports false after running process).
metadata = V2::Metadata.create
secret = V2::Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
params = {
  key: metadata.secret_key,
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [false, false]

## Correctly determines display lines for multi-line secrets
metadata = V2::Metadata.create
secret = V2::Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
params = {
  key: metadata.secret_key,
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.process
logic.display_lines
#=> 9

## Correctly handles a secret without a passphrase
metadata = @create_metadata.call
secret = metadata.load_secret
params = {
  key: metadata.secret_key,
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.process
[logic.secret.has_passphrase?, logic.correct_passphrase, logic.show_secret]
#=> [false, false, true]

## Correctly handles a secret with an incorrect passphrase
metadata = @create_metadata.call
secret = metadata.load_secret
secret.update_passphrase('correct_pass')
params = {
  key: metadata.secret_key,
  passphrase: 'wrong_pass',
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
begin
  logic.process
rescue OT::FormError => e
  [logic.secret.has_passphrase?, logic.correct_passphrase, logic.show_secret, e.message]
end
#=> [true, false, false, "Incorrect passphrase"]

## Correctly handles a secret with an incorrect passphrase (bogus locale)
metadata = @create_metadata.call
secret = metadata.load_secret
secret.update_passphrase('correct_pass')
params = {
  key: metadata.secret_key,
  passphrase: 'wrong_pass',
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'BOGUS')
begin
  logic.process
rescue OT::FormError => e
  [logic.secret.has_passphrase?, logic.correct_passphrase, logic.show_secret, e.message]
end
#=> [true, false, false, "Incorrect passphrase"]

## Correctly handles a secret with a correct passphrase
metadata = @create_metadata.call
secret = metadata.load_secret
secret.update_passphrase('correct_pass')
params = {
  key: metadata.secret_key,
  passphrase: 'correct_pass',
  continue: true
}
logic = V2::Logic::Secrets::RevealSecret.new(@sess, @cust, params, 'en')
logic.process
[logic.secret.has_passphrase?, logic.correct_passphrase, logic.show_secret]
#=> [true, true, true]

# Teardown
@metadata.destroy!
@cust.destroy!
