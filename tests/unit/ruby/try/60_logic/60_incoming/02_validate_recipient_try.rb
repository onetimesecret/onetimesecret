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
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'
OT.boot! :test, false

# Get valid recipient hashes for testing
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]
@security_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Security Team' }[:hash]

## ValidateRecipient succeeds for valid recipient hash
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: @support_hash }
logic.raise_concerns
logic.process
[logic.greenlighted, logic.is_valid]
#=> [true, true]

## ValidateRecipient returns correct success data for valid recipient hash
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: @security_hash }
logic.process
data = logic.success_data
[data[:recipient], data[:valid]]
#=> [@security_hash, true]

## ValidateRecipient rejects invalid hash
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'invalidhash123456' }
logic.process
[logic.greenlighted, logic.is_valid]
#=> [true, false]

## ValidateRecipient returns correct success data for invalid hash
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'badactorhash1234' }
logic.process
data = logic.success_data
[data[:recipient], data[:valid]]
#=> ['badactorhash1234', false]

## ValidateRecipient raises error for empty recipient hash
begin
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: '' }
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Recipient hash is required"

## ValidateRecipient raises error for missing recipient hash
begin
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, {}
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Recipient hash is required"

## ValidateRecipient handles whitespace in hash
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: "  #{@support_hash}  " }
logic.process
data = logic.success_data
[data[:recipient], data[:valid]]
#=> [@support_hash, true]

## ValidateRecipient is case-sensitive for hashes
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: @support_hash.upcase }
logic.process
logic.is_valid
#=> false

## ValidateRecipient validates all configured recipient hashes
public_recipients = OT.incoming_public_recipients
results = public_recipients.map do |r|
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: r[:hash] }
  logic.process
  logic.is_valid
end
results.all?
#=> true

## ValidateRecipient processes params correctly
test_hash = 'testhash123456'
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: test_hash }
logic.recipient_hash
#=> test_hash

# Teardown: Clean up test data
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
