# tests/unit/ruby/try/60_logic/60_incoming/02_validate_recipient_try.rb

# These tests cover the Incoming::ValidateRecipient logic class which handles
# validation of recipient email addresses against the allowed list.
#
# We test:
# 1. Valid recipient validation
# 2. Invalid recipient rejection
# 3. Empty recipient handling
# 4. Feature disabled state
# 5. Whitespace handling

require_relative '../../test_logic'

# Load the app with feature disabled
ENV['INCOMING_ENABLED'] = 'false'
OT.boot! :test, false

# Setup: Create session and customer
@sess = Session.new '127.0.0.1', 'anon'
@cust = Customer.new 'incoming-test@example.com'
@cust.save

## ValidateRecipient raises error when feature is disabled
begin
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'test@example.com' }
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Incoming secrets feature is not enabled"

# Enable feature for subsequent tests
ENV['INCOMING_ENABLED'] = 'true'
OT.boot! :test, false

## ValidateRecipient succeeds for valid recipient
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'support@example.com' }
logic.raise_concerns
logic.process
[logic.greenlighted, logic.is_valid]
#=> [true, true]

## ValidateRecipient returns correct success data for valid recipient
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'security@example.com' }
logic.process
data = logic.success_data
[data[:recipient], data[:valid]]
#=> ['security@example.com', true]

## ValidateRecipient rejects invalid recipient
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'unknown@example.com' }
logic.process
[logic.greenlighted, logic.is_valid]
#=> [true, false]

## ValidateRecipient returns correct success data for invalid recipient
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'badactor@example.com' }
logic.process
data = logic.success_data
[data[:recipient], data[:valid]]
#=> ['badactor@example.com', false]

## ValidateRecipient raises error for empty recipient
begin
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: '' }
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Recipient email is required"

## ValidateRecipient raises error for missing recipient
begin
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, {}
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Recipient email is required"

## ValidateRecipient handles whitespace in recipient
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: '  support@example.com  ' }
logic.process
data = logic.success_data
[data[:recipient], data[:valid]]
#=> ['support@example.com', true]

## ValidateRecipient is case-sensitive
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'SUPPORT@EXAMPLE.COM' }
logic.process
logic.is_valid
#=> false

## ValidateRecipient validates all configured recipients
configured_recipients = OT.conf.dig(:features, :incoming, :recipients) || []
results = configured_recipients.map do |r|
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: r[:email] }
  logic.process
  logic.is_valid
end
results.all?
#=> true

## ValidateRecipient processes params correctly
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'helpdesk@example.com' }
logic.recipient_email
#=> 'helpdesk@example.com'

# Teardown: Clean up test data
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
