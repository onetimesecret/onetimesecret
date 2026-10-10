# try/unit/operations/dlq_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted dead-letter-queue admin operations (epic #42):
#   Onetime::Operations::Dlq::{List, Peek, Replay, Purge}
#
# These are the SINGLE implementation of the DLQ list / peek / replay / purge
# verbs (the `bin/ots queue dlq *` CLI + the colonel `/api/colonel/queues/dlq…`
# endpoints are thin adapters). Covers:
# - List: per-queue summary rows over the fixed DLQ allowlist (read-only, NO audit)
# - Peek: non-destructive peek — the queue is left exactly as found (read-only, NO audit)
# - Replay: re-enqueues to the original queue, records EXACTLY ONE audit event
#   (verb queue.dlq.replay, actor = PUBLIC id, target = queue)
# - Replay empty: no mutation, but the LIVE attempt still records ONE event with
#   outcome: 'no_change' (#4337); a dry-run against an empty queue stays off the
#   operator trail (its preview is an observation on the access trail)
# - Replay dry-run: no mutation, NO operator-trail audit
# - Replay releases each message's worker idempotency claim before it
#   republishes, so a worker processes the replayed message; a dry run releases
#   nothing; a claim that cannot be released keeps that message in the DLQ and
#   is reported without stopping the batch
# - Replay attempts each message at most once per batch: a message that fails
#   returns to the DLQ when the channel closes, not in the middle of the batch
# - Replay commits the republish and the DLQ ack together: a failed ack leaves
#   no republished copy, and a failed commit stops the replay with an
#   outcome-unknown error
# - Purge: empties the queue, records EXACTLY ONE audit event (verb queue.dlq.purge)
# - Purge empty: no mutation, but the LIVE attempt still records ONE event with
#   outcome: 'no_change' (#4337 — the trail must show the firing, not the timing)
# - Purge dry-run: no mutation, NO operator-trail audit (the preview is an
#   observation on the access trail)
#
# The RabbitMQ broker is stubbed by a duck-typed fake connection (no live broker
# needed), so the audit-exactly-once contract can be asserted deterministically.
#
# Run: try --agent try/unit/operations/dlq_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/list'
require 'onetime/operations/dlq/peek'
require 'onetime/operations/dlq/replay'
require 'onetime/operations/dlq/purge'
require 'onetime/jobs/workers/base_worker'

AE = Onetime::ColonelAuditEvent

# --- Duck-typed Bunny fakes -------------------------------------------------

FakeDelivery   = Struct.new(:delivery_tag)
FakeProperties = Struct.new(:message_id, :timestamp, :content_type, :headers)

class FakeExchange
  attr_reader :published

  def initialize(channel)
    @channel   = channel
    @published = []
  end

  # On a channel in transaction mode the message goes out at tx_commit.
  def publish(payload, **opts)
    @channel.transactional { @published << { payload: payload, opts: opts } }
  end

  # Every queue exists here, so nothing is ever returned.
  def on_return(&)
    self
  end
end

class FakeQueue
  attr_reader :consumer_count

  def initialize(messages, consumer_count: 0)
    @messages       = messages.dup   # each: { id:, headers:, content_type:, payload:, ts: }
    @unacked        = {}
    @consumer_count = consumer_count
    @tag            = 0
  end

  def message_count
    @messages.size
  end

  def pop(manual_ack: true)
    m = @messages.shift
    return [nil, nil, nil] unless m

    @tag += 1
    @unacked[@tag] = m
    [FakeDelivery.new(@tag), FakeProperties.new(m[:id], m[:ts], m[:content_type], m[:headers]), m[:payload]]
  end

  def ack(tag)
    @unacked.delete(tag) # permanently removed
  end

  # A requeued message goes back to its original position, the head of the
  # queue, as RabbitMQ does for a classic queue: the next pop returns it again.
  def nack(tag, _multiple, requeue)
    m = @unacked.delete(tag)
    @messages.unshift(m) if requeue && m
  end

  # The broker returns the deliveries a closing channel still holds to the
  # head of the queue, in delivery order.
  def requeue_unacked
    @messages.unshift(*@unacked.sort.map(&:last))
    @unacked.clear
  end

  def purge
    @messages.clear
  end
end

# In transaction mode (tx_select) publishes, acks and nacks wait for
# tx_commit; tx_rollback discards them and leaves the deliveries unacked.
# Closing the channel discards an uncommitted transaction and returns every
# delivery still unacked to the queue.
class FakeChannel
  attr_reader :exchange

  def initialize(queue)
    @queue    = queue
    @exchange = FakeExchange.new(self)
    @open     = true
    @pending  = nil
  end

  def queue(_name, **_opts)
    @queue
  end

  # The replay's passive-declare check of the original queue: every queue
  # exists in these fakes.
  def queue_declare(_name, **_opts)
    true
  end

  def default_exchange
    @exchange
  end

  def tx_select
    @pending ||= []
  end

  def tx_commit
    applied  = @pending
    @pending = []
    applied.each(&:call)
  end

  def tx_rollback
    @pending = []
  end

  def transactional(&op)
    @pending ? @pending << op : op.call
  end

  def ack(tag) = transactional { @queue.ack(tag) }
  def nack(tag, m, r) = transactional { @queue.nack(tag, m, r) }
  def open? = @open

  def close
    @pending = nil
    @queue.requeue_unacked
    @open = false
  end
end

# The optional block receives each channel as it is created, so a test can
# make one of its calls fail.
class FakeConnection
  attr_reader :channels

  def initialize(queue, &on_channel)
    @queue      = queue
    @channels   = []
    @on_channel = on_channel
  end

  def create_channel
    ch = FakeChannel.new(@queue)
    @on_channel&.call(ch)
    @channels << ch
    ch
  end
end

def death_headers(original_queue)
  { 'x-death' => [{ 'queue' => original_queue, 'reason' => 'rejected', 'count' => 2 }] }
end

def sample_messages(n, original: 'billing.event.process')
  (1..n).map do |i|
    {
      id: "msg-#{i}",
      headers: death_headers(original),
      content_type: 'application/json',
      payload: %({"n":#{i}}),
      ts: Time.now.to_i - 60,
    }
  end
end

# The claim step every queue worker runs before it processes a message.
class ClaimProbeWorker
  include Onetime::Jobs::Workers::BaseWorker

  def attempt(message_id)
    claim_for_processing(message_id) ? :processed : :skipped_duplicate
  end
end

# Messages with ids no other test in this file uses, so the claim keys written
# here are this section's own.
def claim_messages(*ids)
  ids.map do |id|
    {
      id: id,
      headers: death_headers('notifications.alert.push'),
      content_type: 'application/json',
      payload: '{}',
      ts: Time.now.to_i - 60,
    }
  end
end

def claim_key(id) = "job:processed:#{id}"

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid
@dlq   = 'dlq.billing.event'

AE.events.clear

# ---- List -------------------------------------------------------------

## Store exposes the fixed DLQ allowlist (bounded — CONTRACT 6)
Onetime::Operations::Dlq::Store.all_dlq_names.include?('dlq.billing.event')
#=> true

## an unknown queue name is rejected by the allowlist
Onetime::Operations::Dlq::Store.valid?('dlq.nope.nope')
#=> false

## resolve prepends the dlq. prefix for a short name, passes a full name through
[Onetime::Operations::Dlq::Store.resolve('billing.event'),
 Onetime::Operations::Dlq::Store.resolve('dlq.billing.event')]
#=> ["dlq.billing.event", "dlq.billing.event"]

## List summarises every configured DLQ (one row per allowlisted queue)
@list_conn = FakeConnection.new(FakeQueue.new(sample_messages(3), consumer_count: 1))
@list = Onetime::Operations::Dlq::List.new(connection: @list_conn).call
@list.dlqs.size
#=> Onetime::Operations::Dlq::Store.all_dlq_names.size

## List is read-only — no audit event recorded
AE.count
#=> 0

# ---- Peek (read-only) -------------------------------------------------

## Peek returns up to `limit` messages and reports the true queue depth
@peek_q    = FakeQueue.new(sample_messages(5))
@peek_conn = FakeConnection.new(@peek_q)
@peek = Onetime::Operations::Dlq::Peek.new(connection: @peek_conn, queue: @dlq, limit: 2).call
[@peek.total_messages, @peek.showing, @peek.messages.size]
#=> [5, 2, 2]

## Peek leaves the queue exactly as found (every peeked message was nack-requeued)
@peek_q.message_count
#=> 5

## Peek surfaces the death diagnosis fields from the x-death header
row = @peek.messages.first
[row[:original_queue], row[:death_reason], row[:death_count]]
#=> ["billing.event.process", "rejected", 2]

## Peek is read-only — still no audit event
AE.count
#=> 0

# ---- Replay: success --------------------------------------------------

## Replay re-enqueues all messages and reports the counts
AE.events.clear
@replay_q    = FakeQueue.new(sample_messages(3))
@replay_conn = FakeConnection.new(@replay_q)
@replay = Onetime::Operations::Dlq::Replay.new(connection: @replay_conn, queue: @dlq, actor: @actor).call
[@replay.status, @replay.replayed, @replay.failed]
#=> [:success, 3, 0]

## the DLQ is now empty (messages were acked off after republish)
@replay_q.message_count
#=> 0

## each message was republished to its original queue
@replay_conn.channels.first.exchange.published.map { |p| p[:opts][:routing_key] }.uniq
#=> ["billing.event.process"]

## exactly ONE audit event was recorded for the replay
AE.count
#=> 1

## the audit event is the replay verb, targeting the queue, actored by the PUBLIC id
@rev = AE.recent(1).first
[@rev['verb'], @rev['target'], @rev['actor']]
#=> ["queue.dlq.replay", "dlq.billing.event", "ur1colonelpub"]

## the audit detail carries the replayed / failed counts
[@rev['detail']['replayed'], @rev['detail']['failed']]
#=> [3, 0]

# ---- Replay: a message with no original queue is dropped + counted failed ----

## a message lacking an x-death queue is nacked-without-requeue (failed), still audited once
AE.events.clear
@bad_q = FakeQueue.new([{ id: 'orphan', headers: {}, content_type: 'application/json', payload: '{}', ts: Time.now.to_i }])
@bad_conn = FakeConnection.new(@bad_q)
@bad = Onetime::Operations::Dlq::Replay.new(connection: @bad_conn, queue: @dlq, actor: @actor).call
[@bad.status, @bad.replayed, @bad.failed, AE.count]
#=> [:success, 0, 1, 1]

## the dropped message is gone from the DLQ, not returned when the channel closes
@bad_q.message_count
#=> 0

## a drop whose commit fails is reported as failed with an unknown outcome, and the replay stops
orphan         = { id: 'orphan-2', headers: {}, content_type: 'application/json', payload: '{}', ts: Time.now.to_i }
@dropfail_q    = FakeQueue.new([orphan, *sample_messages(1)])
@dropfail_conn = FakeConnection.new(@dropfail_q) do |ch|
  ch.define_singleton_method(:tx_commit) { raise(Onetime::Problem, 'commit timed out') }
end
@dropfail      = Onetime::Operations::Dlq::Replay.new(connection: @dropfail_conn, queue: @dlq, actor: @actor).call
[@dropfail.replayed, @dropfail.failed, @dropfail.errors.map { |e| e[:message_id] }]
#=> [0, 1, ['orphan-2']]

## the error says the drop may not have happened
@dropfail.errors.first[:error]
#=> 'Replay stopped, outcome unknown: the broker did not confirm dropping this message, which has no original queue (commit timed out). It may still be in the DLQ.'

## nothing was committed and the message after it was not touched
[@dropfail_conn.channels.first.exchange.published.size, @dropfail_q.message_count]
#=> [0, 2]

# ---- Replay: empty queue mutates nothing, still records the attempt ----

## replaying an empty DLQ is a no-op (:empty) but the LIVE attempt is audited (#4337)
AE.events.clear
@empty = Onetime::Operations::Dlq::Replay.new(connection: FakeConnection.new(FakeQueue.new([])), queue: @dlq, actor: @actor).call
[@empty.status, @empty.replayed, AE.count]
#=> [:empty, 0, 1]

## the empty-replay event keeps the replay verb + queue target, marked outcome: no_change
@eev = AE.recent(1).first
[@eev['verb'], @eev['target'], @eev['result'], @eev['detail']]
#=> ["queue.dlq.replay", "dlq.billing.event", "success", { "outcome" => "no_change", "replayed" => 0, "failed" => 0 }]

## a dry-run against an empty DLQ stays off the operator trail (preview observation only)
AE.events.clear
@empty_dry = Onetime::Operations::Dlq::Replay.new(connection: FakeConnection.new(FakeQueue.new([])), queue: @dlq, actor: @actor, dry_run: true).call
[@empty_dry.status, AE.count]
#=> [:empty, 0]

# ---- Replay: dry-run --------------------------------------------------

## a dry-run reports how many WOULD replay without mutating and without auditing
AE.events.clear
@dry_q = FakeQueue.new(sample_messages(4))
@dry = Onetime::Operations::Dlq::Replay.new(connection: FakeConnection.new(@dry_q), queue: @dlq, actor: @actor, dry_run: true).call
[@dry.status, @dry.would_replay, @dry_q.message_count, AE.count]
#=> [:dry_run, 4, 4, 0]

# ---- Replay: a mid-loop broker failure is audited, then re-raised -----
#
# The Onetime::AuditedFailure mechanism, and the nastiest partial-failure shape
# in the toolbox: the loop republishes and acks message by message — each
# republish able to re-trigger emails and webhooks — and the success record runs
# only at the end. A broker error halfway through therefore fired real side
# effects and previously left NOTHING in the trail. dry_run is in the detail so
# a blown-up preview (sent nothing) is distinguishable from a blown-up live
# replay (may have sent plenty).

## a broker drop mid-loop (pop raises after the first message already went out)
## re-raises the original error
#
# A publish failure is caught PER MESSAGE and counted as `failed`; the uncaught
# shape is the connection itself dying between messages, which is what this
# simulates.
AE.events.clear
@boom_q = FakeQueue.new(sample_messages(3))
boom_pops = [0] # closure counter — an ivar here would land on the FakeQueue
@boom_q.define_singleton_method(:pop) do |**kwargs|
  boom_pops[0] += 1
  raise(Onetime::Problem, 'broker gone') if boom_pops[0] > 1

  super(**kwargs)
end
@boom_conn = FakeConnection.new(@boom_q)
begin
  Onetime::Operations::Dlq::Replay.new(connection: @boom_conn, queue: @dlq, actor: @actor).call
  :no_raise
rescue Onetime::Problem
  :raised
end
#=> :raised

## the first message DID go out — the side effect happened, so the trail must show it
@boom_conn.channels.first.exchange.published.size
#=> 1

## it recorded ONE result: :failure event with the unchanged verb + queue target
@bev = AE.recent(1).first
[AE.count, @bev['verb'], @bev['target'], @bev['result'], @bev['detail']['dry_run']]
#=> [1, "queue.dlq.replay", "dlq.billing.event", "failure", false]

# ---- Replay: releases the workers' idempotency claim -------------------
#
# A worker that rejects a message keeps the claim it took on the message id.
# A replay republishes under the same id, so without a release the worker acks
# the replayed message as a duplicate and does nothing.

## the claim key Replay releases is the one the workers take
Onetime::Jobs::QueueConfig.processing_claim_key('claim-try-a')
#=> "job:processed:claim-try-a"

## a worker that claimed a message and rejected it skips a second delivery of the same id
@probe = ClaimProbeWorker.new
Familia.dbclient.del(claim_key('claim-try-a'), claim_key('claim-try-b'))
[@probe.attempt('claim-try-a'), @probe.attempt('claim-try-a')]
#=> [:processed, :skipped_duplicate]

## replaying the dead-lettered message releases its claim
@claim_conn = FakeConnection.new(FakeQueue.new(claim_messages('claim-try-a', 'claim-try-b')))
@claim_replay = Onetime::Operations::Dlq::Replay.new(connection: @claim_conn, queue: @dlq, actor: @actor).call
[@claim_replay.status, @claim_replay.replayed, @claim_replay.failed, Familia.dbclient.exists?(claim_key('claim-try-a'))]
#=> [:success, 2, 0, false]

## so the worker processes the replayed message instead of skipping it
@probe.attempt('claim-try-a')
#=> :processed

## the replayed message keeps its original message id
@claim_conn.channels.first.exchange.published.map { |p| p[:opts][:message_id] }
#=> ["claim-try-a", "claim-try-b"]

## a dry run releases nothing: the claim is still held afterwards
Familia.dbclient.del(claim_key('claim-try-dry'))
@probe.attempt('claim-try-dry')
@claim_dry = Onetime::Operations::Dlq::Replay.new(connection: FakeConnection.new(FakeQueue.new(claim_messages('claim-try-dry'))), queue: @dlq, actor: @actor, dry_run: true).call
[@claim_dry.status, @probe.attempt('claim-try-dry')]
#=> [:dry_run, :skipped_duplicate]

## a message with no message id has no claim to release and is replayed as before
@noid_conn = FakeConnection.new(FakeQueue.new(claim_messages(nil)))
@noid = Onetime::Operations::Dlq::Replay.new(connection: @noid_conn, queue: @dlq, actor: @actor).call
[@noid.status, @noid.replayed, @noid.failed, @noid_conn.channels.first.exchange.published.size]
#=> [:success, 1, 0, 1]

## a message dropped for having no original queue keeps its claim (nothing is republished)
Familia.dbclient.del(claim_key('claim-try-orphan'))
@probe.attempt('claim-try-orphan')
@orphan = Onetime::Operations::Dlq::Replay.new(connection: FakeConnection.new(FakeQueue.new([{ id: 'claim-try-orphan', headers: {}, content_type: 'application/json', payload: '{}', ts: Time.now.to_i }])), queue: @dlq, actor: @actor).call
[@orphan.failed, Familia.dbclient.exists?(claim_key('claim-try-orphan'))]
#=> [1, true]

## a claim that cannot be released is counted as failed and does not stop the batch
@stuck_q = FakeQueue.new(claim_messages('claim-try-1', 'claim-try-stuck', 'claim-try-3'))
@stuck_conn = FakeConnection.new(@stuck_q)
@stuck_op = Onetime::Operations::Dlq::Replay.new(connection: @stuck_conn, queue: @dlq, actor: @actor)
@stuck_op.define_singleton_method(:release_processing_claim) do |message_id|
  raise(RedisClient::CannotConnectError, 'datastore down') if message_id == 'claim-try-stuck'

  super(message_id)
end
@stuck = @stuck_op.call
[@stuck.status, @stuck.replayed, @stuck.failed]
#=> [:success, 2, 1]

## the failure is reported per message, naming the claim
@stuck.errors.map { |e| [e[:message_id], e[:error]] }
#=> [["claim-try-stuck", "Idempotency claim not released: datastore down"]]

## the message whose claim was not released stays in the DLQ; the others were republished
[@stuck_q.message_count, @stuck_conn.channels.first.exchange.published.map { |p| p[:opts][:message_id] }]
#=> [1, ["claim-try-1", "claim-try-3"]]

# ---- Replay: each message is attempted once per batch ------------------
#
# The broker puts a requeued message back at the head of the DLQ, so a
# message returned in the middle of the batch would be popped again at once
# and use up the attempts meant for the messages behind it.

## a failed publish is counted once and the messages after it are still replayed
@pubfail_q = FakeQueue.new(claim_messages('claim-try-p1', 'claim-try-pfail', 'claim-try-p3'))
@pubfail_conn = FakeConnection.new(@pubfail_q) do |ch|
  ch.exchange.define_singleton_method(:publish) do |payload, **opts|
    raise(Onetime::Problem, 'publish refused') if opts[:message_id] == 'claim-try-pfail'

    super(payload, **opts)
  end
end
@pubfail = Onetime::Operations::Dlq::Replay.new(connection: @pubfail_conn, queue: @dlq, actor: @actor).call
[@pubfail.replayed, @pubfail.failed, @pubfail.errors.map { |e| [e[:message_id], e[:error]] }]
#=> [2, 1, [["claim-try-pfail", "publish refused"]]]

## the message that failed to publish is back in the DLQ; the others were republished
[@pubfail_q.message_count, @pubfail_conn.channels.first.exchange.published.map { |p| p[:opts][:message_id] }]
#=> [1, ["claim-try-p1", "claim-try-p3"]]

# ---- Replay: the republish and the DLQ ack commit together -------------
#
# A message republished while its DLQ entry stays behind is replayed a second
# time by the next replay, which also releases the claim the first copy took.
# Both copies run.

## an ack that fails after the publish leaves no republished copy behind
@ackfail_q = FakeQueue.new(claim_messages('claim-try-ackfail', 'claim-try-after'))
ack_calls = [0] # closure counter: only the first ack fails
@ackfail_conn = FakeConnection.new(@ackfail_q) do |ch|
  ch.define_singleton_method(:ack) do |tag|
    ack_calls[0] += 1
    raise(Onetime::Problem, 'ack lost') if ack_calls[0] == 1

    super(tag)
  end
end
@ackfail = Onetime::Operations::Dlq::Replay.new(connection: @ackfail_conn, queue: @dlq, actor: @actor).call
[@ackfail.replayed, @ackfail.failed, @ackfail.errors.map { |e| [e[:message_id], e[:error]] }]
#=> [1, 1, [["claim-try-ackfail", "ack lost"]]]

## only the next message went out, and the failed one is back in the DLQ
[@ackfail_conn.channels.first.exchange.published.map { |p| p[:opts][:message_id] }, @ackfail_q.message_count]
#=> [["claim-try-after"], 1]

## a second replay sends the message once, so there is one copy in total
@ackfail_again_conn = FakeConnection.new(@ackfail_q)
@ackfail_again = Onetime::Operations::Dlq::Replay.new(connection: @ackfail_again_conn, queue: @dlq, actor: @actor).call
[@ackfail_conn, @ackfail_again_conn].flat_map { |c| c.channels.first.exchange.published }
  .count { |p| p[:opts][:message_id] == 'claim-try-ackfail' }
#=> 1

## a commit that fails is reported as failed with an unknown outcome, and the replay stops
@cfail_q = FakeQueue.new(claim_messages('claim-try-c1', 'claim-try-c2'))
@cfail_conn = FakeConnection.new(@cfail_q) do |ch|
  ch.define_singleton_method(:tx_commit) { raise(Onetime::Problem, 'commit timed out') }
end
@cfail = Onetime::Operations::Dlq::Replay.new(connection: @cfail_conn, queue: @dlq, actor: @actor).call
[@cfail.replayed, @cfail.failed, @cfail.errors.map { |e| e[:message_id] }]
#=> [0, 1, ["claim-try-c1"]]

## the error says the message may already be republished and that replaying it again may repeat it
@cfail.errors.first[:error]
#=> "Replay stopped, outcome unknown: the broker did not confirm the commit (commit timed out). The message may already be republished to notifications.alert.push; replaying it again may repeat its side effects."

## nothing was committed and the message after it was not touched
[@cfail_conn.channels.first.exchange.published.size, @cfail_q.message_count]
#=> [0, 2]

# ---- Purge: success ---------------------------------------------------

## Purge empties the queue and reports the purged count
AE.events.clear
@purge_q = FakeQueue.new(sample_messages(6))
@purge = Onetime::Operations::Dlq::Purge.new(connection: FakeConnection.new(@purge_q), queue: @dlq, actor: @actor).call
[@purge.status, @purge.purged, @purge_q.message_count]
#=> [:success, 6, 0]

## exactly ONE audit event was recorded for the purge
AE.count
#=> 1

## the audit event is the purge verb targeting the queue, with the purged count
@pev = AE.recent(1).first
[@pev['verb'], @pev['target'], @pev['detail']['purged']]
#=> ["queue.dlq.purge", "dlq.billing.event", 6]

# ---- Purge: empty queue mutates nothing, still records the attempt ----

## purging an empty DLQ is a no-op (:empty) but the LIVE attempt is audited (#4337)
AE.events.clear
@pe = Onetime::Operations::Dlq::Purge.new(connection: FakeConnection.new(FakeQueue.new([])), queue: @dlq, actor: @actor).call
[@pe.status, @pe.purged, AE.count]
#=> [:empty, 0, 1]

## the empty-purge event keeps the purge verb + queue target, marked outcome: no_change
@pev = AE.recent(1).first
[@pev['verb'], @pev['target'], @pev['result'], @pev['detail']]
#=> ["queue.dlq.purge", "dlq.billing.event", "success", { "outcome" => "no_change", "purged" => 0 }]

# ---- Purge: dry-run ---------------------------------------------------

## a dry-run reports the in-scope count without deleting and without auditing
AE.events.clear
@pd_q = FakeQueue.new(sample_messages(3))
@pd = Onetime::Operations::Dlq::Purge.new(connection: FakeConnection.new(@pd_q), queue: @dlq, actor: @actor, dry_run: true).call
[@pd.status, @pd.count, @pd.purged, @pd_q.message_count, AE.count]
#=> [:dry_run, 3, 0, 3, 0]

# Cleanup
AE.events.clear
Familia.dbclient.del(*%w[a b dry orphan 1 stuck 3 p1 pfail p3 ackfail after c1 c2].map { |suffix| claim_key("claim-try-#{suffix}") })
