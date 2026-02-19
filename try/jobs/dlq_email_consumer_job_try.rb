# try/jobs/dlq_email_consumer_job_try.rb
#
# frozen_string_literal: true

# Tests the DlqEmailConsumerJob scheduled job logic.
#
# Covers:
#   - AUTH_TEMPLATES constant structure
#   - Config flag gating (enabled?)
#   - Header extraction and cleaning (extract_original_queue, clean_headers)
#   - Idempotency (claim_for_replay) via Redis SET NX
#   - Message routing: raw, auth template, non-auth template
#   - Expired token discard logic
#   - Duplicate message_id skip
#
# Does NOT require RabbitMQ — uses mock channel/delivery/properties objects.

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/dlq_email_consumer_job'

@job = Onetime::Jobs::Scheduled::DlqEmailConsumerJob

# Mock objects for process_message tests.
# These simulate the Bunny objects without requiring a real RabbitMQ connection.

MockDeliveryInfo = Data.define(:delivery_tag)

MockProperties = Data.define(:message_id, :headers, :content_type) do
  def initialize(message_id: nil, headers: nil, content_type: 'application/json')
    super
  end
end

# Records channel operations (ack, nack, publish) for assertion.
class MockChannel
  attr_reader :acks, :nacks, :publishes

  def initialize
    @acks = []
    @nacks = []
    @publishes = []
    @exchange = MockExchange.new(@publishes)
  end

  def ack(delivery_tag)
    @acks << delivery_tag
  end

  def nack(delivery_tag, multiple, requeue)
    @nacks << { tag: delivery_tag, multiple: multiple, requeue: requeue }
  end

  def default_exchange
    @exchange
  end
end

class MockExchange
  def initialize(publishes)
    @publishes = publishes
  end

  def publish(payload, **opts)
    @publishes << { payload: payload, **opts }
  end
end

# Helper to call private class methods on the job
def call_private(method, *args)
  @job.send(method, *args)
end

# Helper to build a results hash
def fresh_results
  { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0 }
end

# Cleanup idempotency keys we create during testing
@cleanup_keys = []

def track_key(key)
  @cleanup_keys << key
  key
end

# TRYOUTS

## AUTH_TEMPLATES contains email_change_confirmation
@job::AUTH_TEMPLATES.key?('email_change_confirmation')
#=> true

## AUTH_TEMPLATES contains password_reset
@job::AUTH_TEMPLATES.key?('password_reset')
#=> true

## AUTH_TEMPLATES contains verify_account
@job::AUTH_TEMPLATES.key?('verify_account')
#=> true

## AUTH_TEMPLATES does not contain secret_link
@job::AUTH_TEMPLATES.key?('secret_link')
#=> false

## AUTH_TEMPLATES does not contain incoming_secret
@job::AUTH_TEMPLATES.key?('incoming_secret')
#=> false

## AUTH_TEMPLATES email_change_confirmation has expected token_field
@job::AUTH_TEMPLATES['email_change_confirmation'][:token_field]
#=> 'confirmation_token'

## AUTH_TEMPLATES verify_account has nil deadline_column (presence check)
@job::AUTH_TEMPLATES['verify_account'][:deadline_column]
#=> nil

## BATCH_SIZE is 50
@job::BATCH_SIZE
#=> 50

## DLQ_NAME is dlq.email.message
@job::DLQ_NAME
#=> 'dlq.email.message'

## enabled? returns false in test config (dlq_consumer_enabled not set to true)
call_private(:enabled?)
#=> false

## enabled? checks jobs.dlq_consumer_enabled config path
OT.conf.dig('jobs', 'dlq_consumer_enabled') == true
#=> false

## extract_original_queue returns queue from x-death headers
headers = { 'x-death' => [{ 'queue' => 'email.message.send', 'reason' => 'rejected' }] }
call_private(:extract_original_queue, headers)
#=> 'email.message.send'

## extract_original_queue returns nil when headers are nil
call_private(:extract_original_queue, nil)
#=> nil

## extract_original_queue returns nil when x-death is missing
call_private(:extract_original_queue, { 'some-other' => 'header' })
#=> nil

## extract_original_queue returns nil when x-death is empty
call_private(:extract_original_queue, { 'x-death' => [] })
#=> nil

## clean_headers strips x-death and x-first-death headers
headers = {
  'x-death' => [{ 'queue' => 'q' }],
  'x-first-death-exchange' => 'dlx.email.message',
  'x-first-death-queue' => 'email.message.send',
  'x-first-death-reason' => 'rejected',
  'content-type' => 'application/json',
  'x-schema-version' => 1,
}
cleaned = call_private(:clean_headers, headers)
[cleaned.key?('x-death'), cleaned.key?('x-first-death-exchange'), cleaned.key?('content-type'), cleaned.key?('x-schema-version')]
#=> [false, false, true, true]

## clean_headers returns empty hash when headers are nil
call_private(:clean_headers, nil)
#=> {}

## claim_for_replay returns true on first claim
key_id = "test-idem-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{key_id}")
call_private(:claim_for_replay, key_id)
#=> true

## claim_for_replay returns false on duplicate claim
key_id2 = "test-idem-dup-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{key_id2}")
call_private(:claim_for_replay, key_id2)
call_private(:claim_for_replay, key_id2)
#=> false

## process_message discards non-auth template (secret_link)
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-non-auth')
props = MockProperties.new
payload = JSON.generate({ 'template' => 'secret_link', 'data' => { 'secret_key' => 'abc' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
results[:discarded_non_auth]
#=> 1

## process_message nacks non-auth template without requeue
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-nack-check')
props = MockProperties.new
payload = JSON.generate({ 'template' => 'incoming_secret', 'data' => {} })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
ch.nacks.first[:requeue]
#=> false

## process_message discards auth template with missing token
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-no-token')
props = MockProperties.new
payload = JSON.generate({ 'template' => 'password_reset', 'data' => {} })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
results[:discarded_expired]
#=> 1

## process_message replays raw email (Rodauth auth email)
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-raw')
msg_id = "raw-replay-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
headers = { 'x-death' => [{ 'queue' => 'email.message.send' }] }
props = MockProperties.new(message_id: msg_id, headers: headers)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'user@example.com', 'from' => 'noreply@example.com', 'subject' => 'Reset', 'body' => 'Click here' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
results[:replayed]
#=> 1

## process_message acks raw email after replay
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-raw-ack')
msg_id = "raw-ack-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
headers = { 'x-death' => [{ 'queue' => 'email.message.send' }] }
props = MockProperties.new(message_id: msg_id, headers: headers)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
ch.acks.include?('tag-raw-ack')
#=> true

## process_message publishes replay to original queue
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-raw-pub')
msg_id = "raw-pub-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
headers = { 'x-death' => [{ 'queue' => 'email.message.send' }] }
props = MockProperties.new(message_id: msg_id, headers: headers)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
ch.publishes.first[:routing_key]
#=> 'email.message.send'

## process_message skips replay when message_id already claimed (idempotency)
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-dup')
msg_id = "dup-check-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
headers = { 'x-death' => [{ 'queue' => 'email.message.send' }] }
props = MockProperties.new(message_id: msg_id, headers: headers)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
# First call claims
call_private(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-first'), props, payload, fresh_results)
# Second call with same message_id should skip
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
[results[:replayed], ch.acks.include?('tag-dup')]
#=> [0, true]

## process_message counts error for invalid JSON
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-bad-json')
props = MockProperties.new
results = fresh_results
call_private(:process_message, ch, di, props, 'not-valid-json{', results)
results[:errors]
#=> 1

## process_message nacks invalid JSON without requeue
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-bad-json2')
props = MockProperties.new
results = fresh_results
call_private(:process_message, ch, di, props, '{bad', results)
ch.nacks.first[:requeue]
#=> false

## process_message errors on missing x-death headers for raw replay
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-no-xdeath')
msg_id = "no-xdeath-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
props = MockProperties.new(message_id: msg_id, headers: nil)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
results[:errors]
#=> 1

## process_message strips x-death headers from replayed message
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-strip')
msg_id = "strip-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
headers = {
  'x-death' => [{ 'queue' => 'email.message.send' }],
  'x-first-death-reason' => 'rejected',
  'x-schema-version' => 1,
}
props = MockProperties.new(message_id: msg_id, headers: headers)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
published_headers = ch.publishes.first[:headers]
[published_headers.key?('x-death'), published_headers.key?('x-first-death-reason'), published_headers.key?('x-schema-version')]
#=> [false, false, true]

## token_expired? returns false when Auth::Database.connection is nil
# This happens when full auth mode is not enabled (simple mode)
config = @job::AUTH_TEMPLATES['password_reset']
call_private(:token_expired?, config, 'some-token-value')
#=> false

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
