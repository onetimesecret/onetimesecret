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
#   - Releasing the worker's idempotency claim before a replay, and leaving
#     the message in the DLQ when the release fails
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

# The DLQ on the job's dedicated channel, settled the way RabbitMQ settles a
# basic.get with manual ack: a popped message stays unacked until it is acked
# or nacked. A nack with requeue, or closing the channel, puts it back at the
# head of the queue, ahead of the messages not popped yet.
class FakeDlqChannel
  attr_reader :popped, :acks, :nacks, :publishes

  def initialize(messages)
    @ready     = messages.dup
    @unacked   = {}
    @popped    = []
    @acks      = []
    @nacks     = []
    @publishes = []
    @next_tag  = 0
    @open      = true
  end

  def queue(_name, **)
    self
  end

  def message_count
    @ready.size
  end

  def pop(manual_ack:)
    message = @ready.shift
    return [nil, nil, nil] unless message

    @next_tag          += 1
    @unacked[@next_tag] = message
    @popped << message[:properties].message_id
    [MockDeliveryInfo.new(delivery_tag: @next_tag), message[:properties], message[:payload]]
  end

  def ack(delivery_tag)
    @acks << @unacked.delete(delivery_tag)[:properties].message_id
  end

  def nack(delivery_tag, _multiple, requeue)
    message = @unacked.delete(delivery_tag)
    @nacks << message[:properties].message_id
    @ready.unshift(message) if requeue
  end

  def default_exchange
    MockExchange.new(@publishes)
  end

  def open?
    @open
  end

  def close
    @open = false
    @ready.unshift(*@unacked.values)
    @unacked.clear
  end

  # Message ids still in the DLQ
  def remaining
    @ready.map { |message| message[:properties].message_id }
  end
end

# Helper to call private class methods on the job
def call_private(method, *args)
  @job.send(method, *args)
end

# Helper to build a results hash
def fresh_results
  { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0, deferred: 0 }
end

# Properties of a raw email dead-lettered from the email queue
def raw_properties(message_id)
  MockProperties.new(message_id: message_id, headers: { 'x-death' => [{ 'queue' => 'email.message.send' }] })
end

RAW_PAYLOAD = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })

# A DLQ entry for FakeDlqChannel
def dlq_message(message_id)
  { properties: raw_properties(message_id), payload: RAW_PAYLOAD }
end

# A copy of the job that reads the DLQ from the given channel, and whose
# release of the worker's idempotency claim raises for the given message ids,
# as it does when the datastore is unreachable. A subclass, so the job itself
# is unchanged for the other test cases.
def job_with(channel: nil, failing_release: [])
  Class.new(@job) do
    define_singleton_method(:acquire_channel) { [nil, channel, false] }
    define_singleton_method(:release_processing_claim) do |message_id|
      raise RedisClient::CannotConnectError, 'datastore down' if failing_release.include?(message_id)

      super(message_id)
    end
  end
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

## enabled? returns false in test config (dlq_consumer.enabled not set to true)
call_private(:enabled?)
#=> false

## enabled? checks jobs.dlq_consumer.enabled config path
OT.conf.dig('jobs', 'dlq_consumer', 'enabled') == true
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

## replaying a message releases the worker's idempotency claim on its id
# The worker's own release is best-effort. A claim left behind would make the
# worker ack the replayed message as a duplicate and never send it.
ch = MockChannel.new
msg_id = "release-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
track_key("job:processed:#{msg_id}")
Familia.dbclient.set("job:processed:#{msg_id}", '1')
results = fresh_results
call_private(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-release'), raw_properties(msg_id), RAW_PAYLOAD, results)
[results[:replayed], ch.publishes.size, Familia.dbclient.exists?("job:processed:#{msg_id}")]
#=> [1, 1, false]

## a message already replayed is dropped without releasing the claim a live copy holds
ch = MockChannel.new
msg_id = "replayed-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
track_key("job:processed:#{msg_id}")
Familia.dbclient.set("dlq:replayed:#{msg_id}", '1')
Familia.dbclient.set("job:processed:#{msg_id}", '1')
results = fresh_results
call_private(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-replayed'), raw_properties(msg_id), RAW_PAYLOAD, results)
[ch.acks, ch.publishes.size, results[:replayed], Familia.dbclient.exists?("job:processed:#{msg_id}")]
#=> [['tag-replayed'], 0, 0, true]

## a message whose claim cannot be released is left unacked and not marked as replayed
ch = MockChannel.new
@deferred_id = "deferred-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{@deferred_id}")
track_key("job:processed:#{@deferred_id}")
Familia.dbclient.set("job:processed:#{@deferred_id}", '1')
results = fresh_results
job_with(failing_release: [@deferred_id]).send(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-deferred'), raw_properties(@deferred_id), RAW_PAYLOAD, results)
[ch.acks, ch.nacks, ch.publishes.size, results[:deferred], results[:errors], Familia.dbclient.exists?("dlq:replayed:#{@deferred_id}")]
#=> [[], [], 0, 1, 0, false]

## so a later run releases the claim and replays it
ch = MockChannel.new
results = fresh_results
call_private(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-deferred-2'), raw_properties(@deferred_id), RAW_PAYLOAD, results)
[results[:replayed], ch.acks, Familia.dbclient.exists?("job:processed:#{@deferred_id}")]
#=> [1, ['tag-deferred-2'], false]

## a batch replays the other messages, pops each message once, and leaves the deferred one in the DLQ
ids = %w[a b c].map { |name| "batch-#{name}-#{SecureRandom.hex(4)}" }
ids.each { |id| track_key("dlq:replayed:#{id}") }
dlq = FakeDlqChannel.new(ids.map { |id| dlq_message(id) })
job_with(channel: dlq, failing_release: [ids[1]]).send(:consume_dlq_batch)
[
  dlq.popped == ids,
  dlq.acks == [ids[0], ids[2]],
  dlq.publishes.map { |p| p[:message_id] } == [ids[0], ids[2]],
  dlq.nacks,
  dlq.remaining == [ids[1]],
  dlq.open?,
]
#=> [true, true, true, [], true, false]

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

## process_message nacks with requeue=false when original queue not found in x-death headers
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-no-xdeath-nack')
msg_id = "no-xdeath-nack-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
props = MockProperties.new(message_id: msg_id, headers: nil)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
results = fresh_results
call_private(:process_message, ch, di, props, payload, results)
ch.nacks.first[:requeue]
#=> false

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
