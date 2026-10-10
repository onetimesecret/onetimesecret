# spec/unit/onetime/operations/dlq/replay_message_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Dlq::Replay with `message_id:` (#4343): replay one
# dead-lettered message by id.
#
# Runs on the stateful fake broker (spec/support/fake_dlq_broker.rb), which
# returns a requeued delivery to its original position and models AMQP
# transactions, so these examples see a scan that re-reads the head (#4650)
# and an ack that is not committed. The email-DLQ group uses the real test
# Valkey for the consumer's reservation scripts, like
# spec/unit/onetime/jobs/scheduled/dlq_email_consumer_job_spec.rb.

require 'spec_helper'
require 'securerandom'
require 'onetime/operations/dlq/replay'

RSpec.describe Onetime::Operations::Dlq::Replay, 'one message by id' do
  let(:actor) { 'ur_colonel_public' }
  let(:dlq) { 'dlq.billing.event' }
  let(:ids) { %w[A B C D E] }
  let(:broker) { DlqFakeBroker.broker(ids) }
  let(:connection) { broker.connection }

  before do
    # Audit writes join the broker's event log, so ordering can be asserted
    # across the two.
    allow(Onetime::ColonelAuditEvent).to receive(:record) do |**kwargs|
      broker.events << [:audit, kwargs[:detail]]
      nil
    end
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
  end

  def replay(message_id, conn: connection, **opts)
    described_class.new(connection: conn, queue: dlq, actor: actor, message_id: message_id, **opts).call
  end

  def pops = broker.events.select { |event| event.first == :pop }.map(&:last)

  def published_ids = broker.published.map { |entry| entry[:opts][:message_id] }

  describe 'a message behind the head' do
    it 'replays only that message and pops each message ahead of it once' do
      result = replay('C')

      expect(result).to have_attributes(
        status: :success, replayed: 1, failed: 0, errors: [], message_id: 'C',
        found: true, outcome: nil, scanned: 3, truncated: false,
      )
      expect(pops).to eq(%w[A B C])
      expect(published_ids).to eq(%w[C])
      expect(broker.published.first[:opts]).to include(routing_key: 'billing.event.process', persistent: true)
    end

    # Blueprint test 6 expected the others to be nack-requeued one by one
    # during the scan. That is the #4650 bug: each would come back to the
    # head and be popped again.
    it 'leaves the other messages in the DLQ in their original order' do
      replay('C')

      expect(broker.ready_ids).to eq(%w[A B D E])
      expect(broker.channels.map(&:unacked)).to all(be_empty)
    end

    it 'returns the messages ahead before the transaction, so no commit carries their nacks' do
      replay('C')

      tx_at = broker.events.index([:tx_select])
      expect(broker.events.index([:nack, 'A'])).to be < tx_at
      expect(broker.events.index([:nack, 'B'])).to be < tx_at
    end

    it 'commits the republish and the DLQ ack together, then writes ONE fail-closed event' do
      replay('C')

      tx_at = broker.events.index([:tx_select])
      expect(broker.events[tx_at..]).to eq([
        [:tx_select],
        [:probe, 'billing.event.process'],
        [:published, 'C', 'billing.event.process'],
        [:ack, 'C'],
        [:tx_commit],
        [:audit, { message_id: 'C', replayed: 1, failed: 0 }],
        [:close],
        [:close],
      ])
      expect(broker.published.first[:opts]).to include(mandatory: true)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.replay', target: dlq, result: :success,
        detail: { message_id: 'C', replayed: 1, failed: 0 }, fail_closed: true,
      )
    end

    it 'adds the operator reason to the event' do
      replay('C', reason: '  ticket 4412  ')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(detail: { message_id: 'C', replayed: 1, failed: 0, reason: 'ticket 4412' }),
      )
    end
  end

  describe 'a message the scan does not see' do
    it 'is not_visible, scans the queue once, changes nothing' do
      result = replay('missing')

      expect(result).to have_attributes(
        status: :not_visible, outcome: 'not_visible', found: false,
        replayed: 0, failed: 0, scanned: 5, truncated: false,
      )
      expect(pops).to eq(%w[A B C D E])
      expect(broker.published).to be_empty
      expect(broker.ready_ids).to eq(ids)
    end

    it 'records the attempt on the operator trail as not_visible, not fail-closed' do
      replay('missing')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.replay', target: dlq, result: :success,
        detail: { message_id: 'missing', scanned: 5, truncated: false, replayed: 0, failed: 0, outcome: 'not_visible' },
      )
    end

    it 'reports truncated when the scan stops at MAX_SCAN with messages behind it' do
      stub_const('Onetime::Operations::Dlq::Store::MAX_SCAN', 2)

      result = replay('E')

      expect(result).to have_attributes(status: :not_visible, scanned: 2, truncated: true)
      expect(pops).to eq(%w[A B])
      expect(broker.ready_ids).to eq(ids)
    end

    it 'treats a queue that is not declared on the broker as not_visible' do
      undeclared = DlqFakeBroker.broker(ids, declared: false)

      result = replay('C', conn: undeclared.connection)

      expect(result).to have_attributes(status: :not_visible, outcome: 'not_visible', scanned: 0, truncated: false)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
        .with(hash_including(detail: hash_including(outcome: 'not_visible')))
    end
  end

  describe 'dry run' do
    it 'finds the message, republishes nothing, and records one preview observation' do
      result = replay('C', dry_run: true)

      expect(result).to have_attributes(status: :dry_run, would_replay: 1, replayed: 0, found: true, scanned: 3)
      expect(broker.published).to be_empty
      expect(broker.ready_ids).to eq(ids)
      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: actor, verb: 'queue.dlq.replay', target: dlq, result: 'preview',
        detail: { message_id: 'C', found: true, would_replay: 1, scanned: 3, dry_run: true },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'previews a miss as not_visible, still off the operator trail' do
      result = replay('missing', dry_run: true)

      expect(result).to have_attributes(status: :not_visible, would_replay: 0, found: false)
      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        hash_including(detail: hash_including(found: false, outcome: 'not_visible', dry_run: true)),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'failures, with the bulk replay\'s per-message rules' do
    it 'rolls back a failed publish and leaves the message in its place' do
      conn = broker.connection do |ch|
        allow(ch.default_exchange).to receive(:publish).and_raise(IOError, 'publish refused')
      end

      result = replay('C', conn: conn)

      expect(result).to have_attributes(status: :success, replayed: 0, failed: 1,
        errors: [{ message_id: 'C', error: 'publish refused' }])
      expect(broker.ready_ids).to eq(ids)
      # Nothing moved, so the event is not fail-closed.
      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(detail: { message_id: 'C', replayed: 0, failed: 1 }, fail_closed: false))
    end

    it 'reports an unconfirmed commit as outcome unconfirmed, never success, fail-closed' do
      conn = broker.connection do |ch|
        allow(ch).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
      end

      result = replay('C', conn: conn)

      expect(result).to have_attributes(status: :unconfirmed, outcome: 'unconfirmed', found: true,
        replayed: 0, failed: 1)
      expect(result.errors.first[:error]).to start_with('Replay stopped, outcome unknown')
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: { message_id: 'C', replayed: 0, failed: 1, outcome: 'unconfirmed' }, fail_closed: true),
      )
    end

    # Not reachable per message today (a message with no original queue is
    # kept, never dropped), but the step must still map to unconfirmed.
    it 'reports an unconfirmed drop as outcome unconfirmed too' do
      op = described_class.new(connection: connection, queue: dlq, actor: actor, message_id: 'C')
      allow(op).to receive(:replay_delivery) do |_channel, _delivery, properties, _payload, results|
        results[:failed] += 1
        results[:errors] << { message_id: properties.message_id, error: 'Replay stopped, outcome unknown: drop' }
        :drop_unconfirmed
      end

      result = op.call

      expect(result).to have_attributes(status: :unconfirmed, outcome: 'unconfirmed', failed: 1)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: hash_including(outcome: 'unconfirmed'), fail_closed: true),
      )
    end

    it 'records a broker failure mid-scan as one failure event and re-raises' do
      conn = broker.connection do |ch|
        allow(ch).to receive(:queue).and_raise(IOError, 'broker gone')
      end

      expect { replay('C', conn: conn) }.to raise_error(IOError, 'broker gone')
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(result: :failure, detail: hash_including(dry_run: false, message_id: 'C')),
      )
    end
  end

  # R1-4: a default-exchange publish to a missing queue is dropped by the
  # broker, so the DLQ ack must not commit with it.
  describe 'an original queue that does not exist' do
    let(:broker) { DlqFakeBroker.broker(ids, name: dlq) }

    it 'is unroutable: checked first, nothing published, the message kept in its place' do
      broker.missing_queues << 'billing.event.process'

      result = replay('C')

      expect(result).to have_attributes(status: :refused, outcome: 'unroutable', found: true,
        replayed: 0, failed: 0)
      expect(result.errors).to match([{ message_id: 'C', error: a_string_including('no queue named billing.event.process') }])
      expect(broker.events).not_to include(a_collection_including(:returned))
      expect(broker.published).to be_empty
      expect(broker.ready_ids).to eq(ids)
    end

    it 'records the attempt as a no-change attempt' do
      broker.missing_queues << 'billing.event.process'

      replay('C')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.replay', target: dlq, result: :success,
        detail: { message_id: 'C', replayed: 0, failed: 0, refused: 'unroutable', outcome: 'no_change' },
      )
    end

    describe 'deleted after the check, before the commit' do
      before do
        commits = 0
        broker.before_commit = lambda do
          commits += 1
          broker.missing_queues << 'billing.event.process' if commits == 1
        end
      end

      it 'puts the returned message back at the end of the DLQ instead of losing it' do
        result = replay('C')

        expect(broker.events).to include([:returned, 'C', 'billing.event.process'], [:enqueued, 'C'])
        expect(broker.ready_ids).to eq(%w[A B D E C])
        expect(result).to have_attributes(status: :refused, outcome: 'unroutable', replayed: 0, failed: 0)
        expect(result.errors.first[:error]).to include('was deleted during the replay', 'put back at the end of the DLQ')
      end

      it 'keeps its x-death headers, so it can be replayed once the queue is back' do
        replay('C')

        broker.missing_queues.clear
        expect(replay('C')).to have_attributes(status: :success, replayed: 1)
      end

      it 'records a fail-closed event, since the DLQ changed' do
        replay('C')

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(detail: { message_id: 'C', replayed: 0, failed: 0, outcome: 'unroutable' }, fail_closed: true),
        )
      end

      it 'says the message may be lost when putting it back fails' do
        commits = 0
        broker.before_commit = lambda do
          commits += 1
          broker.missing_queues << 'billing.event.process' if commits == 1
          raise IOError, 'commit reply lost' if commits == 2
        end

        result = replay('C')

        expect(result).to have_attributes(status: :unconfirmed, outcome: 'unroutable_lost', replayed: 0, failed: 1)
        expect(result.errors.first[:error]).to include('the message may be lost')
        expect(Onetime::ColonelAuditEvent).to have_received(:record)
          .with(hash_including(detail: hash_including(failed: 1, outcome: 'unroutable_lost'), fail_closed: true))
      end
    end
  end

  # Unlike the bulk replay, which drops such a message, the per-message
  # replay keeps it: the operator asked to replay, not to destroy.
  describe 'a message with no original queue' do
    let(:broker) { DlqFakeBroker.broker(%w[A B C], original_queue: nil) }

    it 'is kept in its place with outcome no_original_queue, nothing published' do
      result = replay('B')

      expect(result).to have_attributes(status: :refused, outcome: 'no_original_queue', found: true,
        replayed: 0, failed: 0)
      expect(result.errors).to match([{ message_id: 'B', error: a_string_including('use Discard to remove it') }])
      expect(broker.published).to be_empty
      expect(broker.events).not_to include([:drop, 'B'])
      expect(broker.ready_ids).to eq(%w[A B C])
    end

    it 'records a no-change attempt carrying that outcome' do
      replay('B', reason: 'retry after fix')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.replay', target: dlq, result: :success,
        detail: { message_id: 'B', replayed: 0, failed: 0, refused: 'no_original_queue',
                  reason: 'retry after fix', outcome: 'no_change' },
      )
    end

    it 'does not take the email DLQ reservation for it' do
      email = DlqFakeBroker.broker(%w[A B], original_queue: nil)
      op    = described_class.new(connection: email.connection, queue: 'dlq.email.message', actor: actor,
        message_id: 'B')
      allow(op).to receive(:dbclient).and_raise('the reservation must not be touched')

      expect(op.call).to have_attributes(outcome: 'no_original_queue')
      expect(email.ready_ids).to eq(%w[A B])
    end
  end

  describe 'arguments' do
    it 'refuses count and message_id together' do
      expect { described_class.new(connection: connection, queue: dlq, actor: actor, count: 1, message_id: 'C') }
        .to raise_error(ArgumentError, /exclusive/)
    end

    it 'refuses a blank message_id instead of falling back to a bulk replay' do
      expect { described_class.new(connection: connection, queue: dlq, actor: actor, message_id: ' ') }
        .to raise_error(ArgumentError, /blank/)
    end
  end

  # F6: an operator replay must not send an email the DLQ consumer already
  # sent or is sending. Real Valkey, the consumer's own scripts.
  describe 'on the email DLQ' do
    let(:consumer) { Onetime::Jobs::Scheduled::DlqEmailConsumerJob }
    let(:dlq) { consumer::DLQ_NAME }
    let(:target) { "test-op-replay-#{SecureRandom.uuid}" }
    let(:ids) { ['ahead', target, 'behind'] }
    let(:broker) { DlqFakeBroker.broker(ids, original_queue: 'email.message.send') }
    let(:redis) { Familia.dbclient }
    let(:completed_key) { consumer.replayed_marker_key(target) }
    let(:reservation_key) { consumer.reservation_key(target) }
    let(:claim_key) { Onetime::Jobs::QueueConfig.processing_claim_key(target) }

    after { redis.del(completed_key, reservation_key, claim_key) }

    it 'refuses an id the consumer already republished, and leaves the message' do
      redis.set(completed_key, 'completed', ex: 60)

      result = replay(target)

      expect(result).to have_attributes(status: :refused, outcome: 'already_replayed', found: true,
        replayed: 0, failed: 0)
      expect(result.errors.first[:error]).to include('would send the email twice')
      expect(broker.published).to be_empty
      expect(broker.ready_ids).to eq(ids)
      expect(redis.get(completed_key)).to eq('completed')
      expect(redis.get(reservation_key)).to be_nil
    end

    it 'records the refusal as a no-change attempt' do
      redis.set(completed_key, 'completed', ex: 60)

      replay(target)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.replay', target: dlq, result: :success,
        detail: { message_id: target, replayed: 0, failed: 0, refused: 'already_replayed', outcome: 'no_change' },
      )
    end

    it 'refuses an id another replay has reserved, and leaves its reservation' do
      redis.set(reservation_key, 'publishing:consumer-run', ex: 60)

      result = replay(target)

      expect(result).to have_attributes(status: :refused, outcome: 'replay_in_progress')
      expect(broker.published).to be_empty
      expect(broker.ready_ids).to eq(ids)
      expect(redis.get(reservation_key)).to eq('publishing:consumer-run')
    end

    it 'refuses an id with a legacy marker, which does not prove the replay completed' do
      redis.set(completed_key, '1', ex: 60)

      expect(replay(target)).to have_attributes(status: :refused, outcome: 'replay_in_progress')
      expect(broker.published).to be_empty
    end

    it 'publishes while holding the publishing reservation, so the consumer would hold off' do
      seen = nil
      conn = broker.connection do |ch|
        allow(ch.default_exchange).to receive(:publish).and_wrap_original do |original, *args, **kwargs|
          seen = redis.get(reservation_key)
          original.call(*args, **kwargs)
        end
      end

      replay(target, conn: conn)

      expect(seen).to start_with('publishing:')
    end

    it 'replays a clear id, releases the worker claim, and leaves no reservation or marker behind' do
      redis.set(claim_key, '1', ex: 60)

      result = replay(target)

      expect(result).to have_attributes(status: :success, replayed: 1)
      expect(published_ids).to eq([target])
      expect(broker.ready_ids).to eq(%w[ahead behind])
      expect(redis.exists?(claim_key)).to be(false)
      expect(redis.get(reservation_key)).to be_nil
      # A completed marker would make the consumer drop the replayed copy if
      # it dead-letters again within the hour.
      expect(redis.get(completed_key)).to be_nil
    end

    it 'releases the reservation when the publish is rolled back' do
      conn = broker.connection do |ch|
        allow(ch.default_exchange).to receive(:publish).and_raise(IOError, 'publish refused')
      end

      expect(replay(target, conn: conn)).to have_attributes(replayed: 0, failed: 1)
      expect(redis.get(reservation_key)).to be_nil
      expect(broker.ready_ids).to eq(ids)
    end

    it 'keeps the publishing reservation when the commit outcome is unknown' do
      conn = broker.connection do |ch|
        allow(ch).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
      end

      replay(target, conn: conn)

      expect(redis.get(reservation_key)).to start_with('publishing:')
      expect(redis.ttl(reservation_key)).to be_between(1, Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL)
    end

    it 'does not publish when the reservation cannot be taken' do
      op = described_class.new(connection: connection, queue: dlq, actor: actor, message_id: target)
      failing = double('dbclient')
      allow(failing).to receive(:eval).and_raise(RedisClient::CannotConnectError, 'datastore down')
      allow(op).to receive(:dbclient).and_return(failing)

      result = op.call

      expect(result).to have_attributes(status: :success, replayed: 0, failed: 1)
      expect(result.errors.first[:error]).to eq('Replay reservation not taken: datastore down')
      expect(broker.published).to be_empty
      expect(broker.ready_ids).to eq(ids)
    end
  end
end
