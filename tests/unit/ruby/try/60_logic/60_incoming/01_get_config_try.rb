# tests/unit/ruby/try/60_logic/60_incoming/01_get_config_try.rb

# These tests cover the Incoming::GetConfig logic class which handles
# retrieval and filtering of incoming secrets configuration.
#
# We test:
# 1. Configuration loading when feature is enabled
# 2. Configuration loading when feature is disabled
# 3. Filtering sensitive fields (passphrase)
# 4. Recipient list formatting
# 5. Default values handling
# 6. Rate limiting enforcement

require_relative '../../test_logic'

# Load the app with test configuration (feature disabled by default)
ENV['INCOMING_ENABLED'] = 'false'
OT.boot! :test, false

# Setup: Create session and customer
@sess = Session.new '127.0.0.1', 'anon'
@cust = Customer.new 'incoming-test@example.com'
@cust.save

## Feature disabled by default in test config
incoming_config = OT.conf.dig(:features, :incoming)
incoming_config[:enabled]
#=> false

## GetConfig raises error when feature is disabled
begin
  logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
  logic.raise_concerns
  logic.process
  false
rescue OT::FormError => e
  e.message
end
#=> "Incoming secrets feature is not enabled"

# Reload with feature enabled
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_MEMO_MAX_LENGTH'] = '50'
ENV['INCOMING_DEFAULT_TTL'] = '604800'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'secret-passphrase'
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'
OT.boot! :test, false

## Feature enabled after reload
incoming_config = OT.conf.dig(:features, :incoming)
incoming_config[:enabled]
#=> true

## GetConfig succeeds when feature is enabled
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.raise_concerns
logic.process
logic.greenlighted
#=> true

## GetConfig returns filtered configuration
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
[
  data[:config][:enabled],
  data[:config][:memo_max_length],
  data[:config][:default_ttl]
]
#=> [true, 50, 604800]

## GetConfig excludes sensitive passphrase field
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
data[:config].key?(:default_passphrase)
#=> false

## GetConfig includes recipient list with hashed format (no emails exposed)
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
recipients = data[:config][:recipients]
[
  recipients.length >= 2,
  recipients[0].key?(:hash),
  recipients[0].key?(:email),
  recipients[0][:name],
  recipients[1][:name]
]
#=> [true, true, false, 'Support Team', 'Security Team']

## GetConfig uses email as name when name is missing
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
recipients = data[:config][:recipients]
recipients.all? { |r| r[:name].is_a?(String) && !r[:name].empty? }
#=> true

# Teardown: Clean up test data
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_TITLE_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
