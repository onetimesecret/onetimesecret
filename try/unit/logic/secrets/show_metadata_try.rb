# try/60_logic/21_logic_secrets_show_metadata_try.rb

# These tryouts test the ShowMetadata logic functionality in the Onetime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a ShowMetadata logic with various arguments
# 2. Testing the visibility of different elements based on metadata state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the ShowMetadata logic correctly handles different scenarios
# and properly initializes based on the provided arguments.

require_relative '../../../support/test_logic'

OT.boot! :test, false

@email = "tryouts+#{Time.now.to_i}@onetimesecret.com"
@cust = Customer.create @email

# Define a lambda to create and return a new metadata instance
@create_metadata = lambda {
  metadata = Metadata.create
  secret = Secret.create(value: "This is a secret message")
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
end

@sess = MockSession.new

## Can create a ShowMetadata logic with all arguments
params = {}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## Correctly sets basic success_data
params = {}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
res = logic.success_data
res.keys
[:record, :details]
#=> [:record, :details]

## Has some essential settings
params = {}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
[logic.site['host'], logic.authentication['enabled'], logic.domains_enabled]
#=> ["127.0.0.1:3000", true, false]

## Raises an exception when there's no metadata (no metadata param)
params = {}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
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
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process_params
begin
  logic.raise_concerns
rescue Onetime::MissingSecret
  true
end
#=> true

## No exceptions raised when metadata can be loaded
params = {
  key: @metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.raise_concerns
@metadata.key
#=> @metadata.key

## Generates correct share URI
params = {
  key: @metadata.key
}
@this_logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
@this_logic.raise_concerns
@this_logic.process
@this_logic.share_url
#=> "#{@this_logic.baseuri}/secret/#{@this_logic.secret.key}"

## Share domain in site.host by default
metadata = @create_metadata.call
params = {
  key: metadata.key
}
@this_logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
@this_logic.process
"https://#{@this_logic.site['host']}"
#=> @this_logic.share_domain

## Share domain is still site.host even when the metadata has it set if domains is not enabled
metadata = @create_metadata.call
metadata.share_domain! "example.com"
params = {
  key: metadata.key
}
@this_logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
@this_logic.process
["https://#{@this_logic.site['host']}", @this_logic.domains_enabled]
#=> [@this_logic.share_domain, false]

## Share domain is processed correctly when the metadata has it set and domains is enabled
metadata = @create_metadata.call
metadata.share_domain! "example.com"
params = {
  key: metadata.key
}
@this_logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
@this_logic.instance_variable_set(:@domains_enabled, true)
@this_logic.process
["https://example.com", @this_logic.domains_enabled]
#=> [@this_logic.share_domain, true]

## Sets locale correctly
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, {}, 'es')
logic.locale
#=> 'es'

## Falls back to nil locale if not provided
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, {}, nil)
logic.locale
#=> nil

## Correctly sets expiration stamp
@metadata.secret_ttl = 3600 * 24 * 2
@metadata.save
params = {
  key: @metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
logic.natural_expiration
#=> "2 days"

## Knows that the metadata has been viewed b/c process has been called several times already
params = {
  key: @metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
[logic.metadata.state, logic.show_secret_link]
#=> ["viewed", false]

## Shows secret link when viewed for the first time (i.e. processed)
metadata = @create_metadata.call
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
[logic.metadata.state, logic.show_secret_link]
#=> ["viewed", true]

## Doesn't show secret link when for the second time though
metadata = @create_metadata.call
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
logic.process
[logic.metadata.state, logic.show_secret_link]
#=> ["viewed", false]

## Hides secret link when metadata is in received state
metadata = @create_metadata.call
metadata.received!
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
[logic.metadata.state, logic.show_secret_link]
#=> ["received", false]

## Asking the logic about whether the secret value is a single line returns nil when no secret
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, {}, 'en')
logic.one_liner
#=> nil

## Correctly determines if secret is a one-liner if the secret is readable
metadata = @create_metadata.call
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [true, true]

## Correctly determines if secret is a one-liner if the secret is readable
metadata = @create_metadata.call
secret = metadata.load_secret
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
secret.received!
logic.process
[secret.viewable?, logic.one_liner]
#=> [false, nil]

## Correctly determines if secret is NOT a one-liner if the secret is readable
metadata = Metadata.create
secret = Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
[logic.secret.viewable?, logic.one_liner]
#=> [true, false]

## Correctly determines display lines for multi-line secrets
metadata = Metadata.create
secret = Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
params = {
  key: metadata.key
}
logic = Logic::Secrets::ShowMetadata.new(@sess, @cust, params, 'en')
logic.process
logic.display_lines
#=> 9

# Teardown
@metadata.destroy!
@cust.destroy!
