# tests/unit/ruby/try/60_logic/60_incoming/06_rate_limiting_try.rb

# These tests verify rate limiting enforcement on incoming endpoints:
# 1. CreateIncomingSecret applies limit_action :create_secret
# 2. CreateIncomingSecret applies limit_action :email_recipient
# 3. GetConfig applies limit_action :get_page
# 4. Exceeding a rate limit raises OT::LimitExceeded
# 5. Rate limit counters increment on each call

require_relative '../../test_logic'

# Boot with feature enabled and recipients configured
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_DEFAULT_TTL'] = '3600'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'test-passphrase-rate'
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'
OT.boot! :test, true

@sess = Session.new '127.0.0.1', 'anon'
@cust = Customer.new 'rate-limit-test@example.com'
@cust.save
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]
@eid = @sess.external_identifier

# Register rate limit events with string keys (matching production
# behavior where IndifferentHash config stores all keys as strings)
@orig_create = RateLimit.event_limit(:create_secret)
@orig_email = RateLimit.event_limit(:email_recipient)
@orig_page = RateLimit.event_limit(:get_page)
RateLimit.register_event 'create_secret', 2
RateLimit.register_event 'email_recipient', 100
RateLimit.register_event 'get_page', 2

# Clear counters before tests
RateLimit.clear! @eid, :create_secret
RateLimit.clear! @eid, :email_recipient
RateLimit.clear! @eid, :get_page

## CreateIncomingSecret raise_concerns increments create_secret counter
params = {
  secret: {
    memo: 'Rate Test',
    secret: 'test content',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
@sess.event_get(:create_secret)
#=> 1

## CreateIncomingSecret raise_concerns also increments email_recipient counter
@sess.event_get(:email_recipient)
#=> 1

## Counters increment on subsequent calls
RateLimit.clear! @eid, :create_secret
RateLimit.clear! @eid, :email_recipient
params = {
  secret: {
    memo: 'Rate Test 2',
    secret: 'more content',
    recipient: @support_hash
  }
}
2.times do
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
end
@sess.event_get(:create_secret)
#=> 2

## Exceeding create_secret rate limit raises LimitExceeded
begin
  p = {
    secret: {
      memo: 'Exceed Test',
      secret: 'content',
      recipient: @support_hash
    }
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, p
  logic.raise_concerns
  false
rescue OT::LimitExceeded
  true
end
#=> true

## GetConfig raise_concerns increments get_page counter
RateLimit.clear! @eid, :get_page
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.raise_concerns
@sess.event_get(:get_page)
#=> 1

## get_page counter increments on subsequent calls
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.raise_concerns
@sess.event_get(:get_page)
#=> 2

## Exceeding get_page rate limit raises LimitExceeded
begin
  logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
  logic.raise_concerns
  false
rescue OT::LimitExceeded
  true
end
#=> true

# Restore original limits and clean up
RateLimit.register_event 'create_secret', @orig_create
RateLimit.register_event 'email_recipient', @orig_email
RateLimit.register_event 'get_page', @orig_page
RateLimit.clear! @eid, :create_secret
RateLimit.clear! @eid, :email_recipient
RateLimit.clear! @eid, :get_page

# Teardown
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
