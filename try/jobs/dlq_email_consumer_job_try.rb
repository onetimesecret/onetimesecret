# try/jobs/dlq_email_consumer_job_try.rb
#
# frozen_string_literal: true

# Tests the DlqEmailConsumerJob scheduled job logic.
#
# Covers:
#   - AUTH_TEMPLATES constant structure
#   - Config flag gating (enabled?)
#   - Header extraction and cleaning (extract_original_queue, clean_headers)
#   - Idempotency (reserve_replay): an owned reservation per message id,
#     and a completed marker written only after the commit
#   - Message routing: raw, auth template, non-auth template
#   - Expired token discard logic
#   - Duplicate message_id skip
#   - Releasing the worker's idempotency claim before a replay, and leaving
#     the message in the DLQ when the datastore fails or a legacy marker is
#     present
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

  def tx_select; end
  def tx_commit; end
  def tx_rollback; end
end

class MockExchange
  def initialize(publishes)
    @publishes = publishes
  end

  def on_return; end

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

  def tx_select; end
  def tx_commit; end
  def tx_rollback; end

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

# Helper to build a results hash, as consume_dlq_batch does
def fresh_results
  call_private(:new_results)
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
# replay reservation raises for the given message ids, as it does when the
# datastore is unreachable. A subclass, so the job itself is unchanged for
# the other test cases.
def job_with(channel: nil, failing_reserve: [])
  Class.new(@job) do
    define_singleton_method(:acquire_channel) { [nil, channel, false] }
    define_singleton_method(:reserve_replay) do |message_id, owner|
      raise RedisClient::CannotConnectError, 'datastore down' if failing_reserve.include?(message_id)

      super(message_id, owner)
    end
  end
end

# A datastore client that runs a block once, right after the first command it
# passes on, so another scheduler run can act between two of the job's steps.
class InterleavingClient < SimpleDelegator
  def initialize(client, &between)
    super(client)
    @between = between
  end

  def method_missing(name, *args, **kwargs, &)
    result   = super
    between  = @between
    @between = nil
    between&.call
    result
  end

  def respond_to_missing?(name, include_private = false) = super
end

# Two scheduler runs that pop DLQ entries with the same message id and
# overlap: right after the first run's first datastore command (its
# reservation), the second run processes its copy. Then the first run
# finishes its replay.
#
# @return [Array] publishes across both runs, the first run's replayed
#   count, the second run's deferred count, and the second run's acks and
#   nacks
def overlapping_replays(message_id)
  first_ch  = MockChannel.new
  second_ch = MockChannel.new
  first     = fresh_results
  second    = fresh_results
  client    = InterleavingClient.new(Familia.dbclient) do
    call_private(:process_message, second_ch, MockDeliveryInfo.new(delivery_tag: 'tag-second'),
      raw_properties(message_id), RAW_PAYLOAD, second)
  end
  Class.new(@job) { define_singleton_method(:dbclient) { client } }
    .send(:process_message, first_ch, MockDeliveryInfo.new(delivery_tag: 'tag-first'),
      raw_properties(message_id), RAW_PAYLOAD, first)
  [first_ch.publishes.size + second_ch.publishes.size, first[:replayed], second[:deferred], second_ch.acks, second_ch.nacks]
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

## extract_original_queue returns nil when an x-death entry is not a table
call_private(:extract_original_queue, { 'x-death' => ['invalid'] })
#=> nil

## extract_original_queue returns nil when x-death is not an array
[call_private(:extract_original_queue, { 'x-death' => 'invalid' }), call_private(:extract_original_queue, { 'x-death' => { 'queue' => 'q' } })]
#=> [nil, nil]

## extract_original_queue returns nil when the queue name is empty or not a string
[call_private(:extract_original_queue, { 'x-death' => [{ 'queue' => '' }] }), call_private(:extract_original_queue, { 'x-death' => [{ 'queue' => 7 }] })]
#=> [nil, nil]

## process_message nacks a raw replay with malformed x-death without requeue
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-bad-xdeath')
props = MockProperties.new(message_id: "bad-xdeath-#{SecureRandom.hex(4)}", headers: { 'x-death' => ['invalid'] })
results = fresh_results
call_private(:process_message, ch, di, props, JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } }), results)
[ch.nacks.map { |nack| nack[:requeue] }, ch.publishes.size, results[:errors], results[:deferred]]
#=> [[false], 0, 1, 0]

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

## reserve_replay reserves an id nobody holds
key_id = "test-idem-#{SecureRandom.hex(4)}"
track_key("dlq:replay:reservation:#{key_id}")
call_private(:reserve_replay, key_id, SecureRandom.uuid)
#=> 1

## reserve_replay defers an id another owner holds
key_id2 = "test-idem-dup-#{SecureRandom.hex(4)}"
track_key("dlq:replay:reservation:#{key_id2}")
call_private(:reserve_replay, key_id2, SecureRandom.uuid)
call_private(:reserve_replay, key_id2, SecureRandom.uuid)
#=> 0

## the reservation expires after RESERVATION_TTL
key_id3 = "test-idem-ttl-#{SecureRandom.hex(4)}"
track_key("dlq:replay:reservation:#{key_id3}")
call_private(:reserve_replay, key_id3, SecureRandom.uuid)
Familia.dbclient.ttl("dlq:replay:reservation:#{key_id3}").between?(1, @job::RESERVATION_TTL)
#=> true

## a completed replay marks the id completed for the idempotency TTL and drops the reservation
key_id4 = "test-idem-done-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{key_id4}")
track_key("dlq:replay:reservation:#{key_id4}")
call_private(:process_message, MockChannel.new, MockDeliveryInfo.new(delivery_tag: 'tag-done'), raw_properties(key_id4), RAW_PAYLOAD, fresh_results)
[
  Familia.dbclient.get("dlq:replayed:#{key_id4}"),
  Familia.dbclient.ttl("dlq:replayed:#{key_id4}").between?(1, Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL),
  Familia.dbclient.exists?("dlq:replay:reservation:#{key_id4}"),
]
#=> ['completed', true, false]

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

## process_message skips replay when message_id already completed (idempotency)
ch = MockChannel.new
di = MockDeliveryInfo.new(delivery_tag: 'tag-dup')
msg_id = "dup-check-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
headers = { 'x-death' => [{ 'queue' => 'email.message.send' }] }
props = MockProperties.new(message_id: msg_id, headers: headers)
payload = JSON.generate({ 'raw' => true, 'email' => { 'to' => 'u@e.com' } })
# First call completes the replay
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
Familia.dbclient.set("dlq:replayed:#{msg_id}", 'completed')
Familia.dbclient.set("job:processed:#{msg_id}", '1')
results = fresh_results
call_private(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-replayed'), raw_properties(msg_id), RAW_PAYLOAD, results)
[ch.acks, ch.publishes.size, results[:replayed], Familia.dbclient.exists?("job:processed:#{msg_id}")]
#=> [['tag-replayed'], 0, 0, true]

## a legacy replay marker, written before publishing, defers the message instead of dropping it
ch = MockChannel.new
msg_id = "legacy-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{msg_id}")
track_key("dlq:replay:reservation:#{msg_id}")
Familia.dbclient.set("dlq:replayed:#{msg_id}", '1', ex: 60)
results = fresh_results
call_private(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-legacy'), raw_properties(msg_id), RAW_PAYLOAD, results)
[ch.acks, ch.nacks, ch.publishes.size, results[:deferred], Familia.dbclient.exists?("dlq:replay:reservation:#{msg_id}")]
#=> [[], [], 0, 1, false]

## an overlapping run that pops another copy of an id being replayed defers it: one publish
@race_id = "race-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{@race_id}")
track_key("dlq:replay:reservation:#{@race_id}")
overlapping_replays(@race_id)
#=> [1, 1, 1, [], []]

## a message whose replay reservation fails on a datastore error is left unacked and not marked as replayed
ch = MockChannel.new
@deferred_id = "deferred-#{SecureRandom.hex(4)}"
track_key("dlq:replayed:#{@deferred_id}")
track_key("job:processed:#{@deferred_id}")
Familia.dbclient.set("job:processed:#{@deferred_id}", '1')
results = fresh_results
job_with(failing_reserve: [@deferred_id]).send(:process_message, ch, MockDeliveryInfo.new(delivery_tag: 'tag-deferred'), raw_properties(@deferred_id), RAW_PAYLOAD, results)
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
job_with(channel: dlq, failing_reserve: [ids[1]]).send(:consume_dlq_batch)
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
