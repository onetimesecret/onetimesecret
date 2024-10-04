# frozen_string_literal: true

# These tryouts test the ShowSecret logic functionality in the OneTime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a ShowSecret logic with various arguments
# 2. Testing the visibility of different elements based on metadata state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the ShowSecret logic correctly handles different scenarios
# and properly initializes based on the provided arguments.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

@email = "tryouts+#{Time.now.to_i}@onetimesecret.com"
@cust = OT::Customer.create @email

# Define a lambda to create and return a new metadata instance
@create_metadata = lambda {
  metadata = OT::Metadata.create
  secret = OT::Secret.create(value: "This is a secret message")
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

## Can create a ShowSecret logic with all arguments
params = {}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## Correctly sets basic success_data
params = {}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
res = logic.success_data
res.keys
[:record, :details]
#=> [:record, :details]

## Has some essential settings
params = {}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
[logic.site[:host], logic.authentication[:enabled], logic.domains_enabled]
#=> ["127.0.0.1:3000", true, false]

## Raises an exception when there's no metadata (no metadata param)
params = {}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
@this_logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
@this_logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
@this_logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
@this_logic.instance_variable_set(:@domains_enabled, true)
@this_logic.process
[@this_logic.share_domain, @this_logic.domains_enabled]
#=> ["https://example.com", true]

## Sets locale correctly
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, {}, 'es')
logic.locale
#=> 'es'

## Falls back to nil locale if not provided
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, {}, nil)
logic.locale
#=> nil

## Asking the logic about whether the secret value is a single line returns nil when no secret
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, {}, 'en')
logic.one_liner
#=> nil

## Cannot determine if secret is a one-liner when the logic.show_secret is false, even if the secret itself is viewable
metadata = @create_metadata.call
params = {
  key: metadata.secret_key
}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
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
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
[logic.secret.viewable?, logic.show_secret, logic.one_liner, logic.secret.can_decrypt?]
#=> [false, true, true, true]

## Correctly determines if secret is a one-liner if the secret is readable
metadata = @create_metadata.call
secret = metadata.load_secret
params = {
  key: metadata.secret_key
}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
secret.received!
logic.process
[secret.viewable?, logic.one_liner]
#=> [false, nil]

## Correctly determines if secret is NOT a one-liner (see note above
## about why logic.secret.viewable? reports false after running process).
metadata = OT::Metadata.create
secret = OT::Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
params = {
  key: metadata.secret_key,
  continue: true
}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [false, false]

## Correctly determines display lines for multi-line secrets
metadata = OT::Metadata.create
secret = OT::Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
params = {
  key: metadata.secret_key,
  continue: true
}
logic = Onetime::Logic::Secrets::ShowSecret.new(@sess, @cust, params, 'en')
logic.process
logic.display_lines
#=> 9

# Teardown
@metadata.destroy!
@cust.destroy!
