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
# - Replay empty / dry-run: no mutation, NO audit
# - Purge: empties the queue, records EXACTLY ONE audit event (verb queue.dlq.purge)
# - Purge empty / dry-run: no mutation, NO audit
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

AE = Onetime::AdminAuditEvent

# --- Duck-typed Bunny fakes -------------------------------------------------

FakeDelivery   = Struct.new(:delivery_tag)
FakeProperties = Struct.new(:message_id, :timestamp, :content_type, :headers)

class FakeExchange
  attr_reader :published

  def initialize
    @published = []
  end

  def publish(payload, **opts)
    @published << { payload: payload, opts: opts }
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

  def nack(tag, _multiple, requeue)
    m = @unacked.delete(tag)
    @messages.push(m) if requeue && m
  end

  def purge
    @messages.clear
  end
end

class FakeChannel
  attr_reader :exchange

  def initialize(queue)
    @queue    = queue
    @exchange = FakeExchange.new
    @open     = true
  end

  def queue(_name, **_opts)
    @queue
  end

  def default_exchange
    @exchange
  end

  def ack(tag) = @queue.ack(tag)
  def nack(tag, m, r) = @queue.nack(tag, m, r)
  def open? = @open
  def close = (@open = false)
end

class FakeConnection
  attr_reader :channels

  def initialize(queue)
    @queue    = queue
    @channels = []
  end

  def create_channel
    ch = FakeChannel.new(@queue)
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

# ---- Replay: empty queue is a no-op -----------------------------------

## replaying an empty DLQ is a no-op (:empty), records NO audit
AE.events.clear
@empty = Onetime::Operations::Dlq::Replay.new(connection: FakeConnection.new(FakeQueue.new([])), queue: @dlq, actor: @actor).call
[@empty.status, @empty.replayed, AE.count]
#=> [:empty, 0, 0]

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

# ---- Purge: empty queue is a no-op ------------------------------------

## purging an empty DLQ is a no-op (:empty), records NO audit
AE.events.clear
@pe = Onetime::Operations::Dlq::Purge.new(connection: FakeConnection.new(FakeQueue.new([])), queue: @dlq, actor: @actor).call
[@pe.status, @pe.purged, AE.count]
#=> [:empty, 0, 0]

# ---- Purge: dry-run ---------------------------------------------------

## a dry-run reports the in-scope count without deleting and without auditing
AE.events.clear
@pd_q = FakeQueue.new(sample_messages(3))
@pd = Onetime::Operations::Dlq::Purge.new(connection: FakeConnection.new(@pd_q), queue: @dlq, actor: @actor, dry_run: true).call
[@pd.status, @pd.count, @pd.purged, @pd_q.message_count, AE.count]
#=> [:dry_run, 3, 0, 3, 0]

# Cleanup
AE.events.clear
