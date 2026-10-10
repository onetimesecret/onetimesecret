# spec/unit/onetime/operations/dlq/discard_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Dlq::Discard (#4343): drop one dead-lettered message by
# id.
#
# Runs on the stateful fake broker (spec/support/fake_dlq_broker.rb): a
# requeued delivery returns to its original position and acks wait for
# tx_commit, so these examples see a scan that re-reads the head (#4650) and
# an audit event written before the drop was confirmed.

require 'spec_helper'
require 'onetime/operations/dlq/discard'

RSpec.describe Onetime::Operations::Dlq::Discard do
  let(:actor) { 'ur_colonel_public' }
  let(:dlq) { 'dlq.billing.event' }
  let(:ids) { %w[A B C D E] }
  let(:broker) { DlqFakeBroker.broker(ids) }
  let(:connection) { broker.connection }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record) do |**kwargs|
      broker.events << [:audit, kwargs[:result], kwargs[:detail]]
      nil
    end
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
  end

  def discard(message_id, conn: connection, **opts)
    described_class.new(connection: conn, queue: dlq, message_id: message_id, actor: actor, **opts).call
  end

  def pops = broker.events.select { |event| event.first == :pop }.map(&:last)

  describe 'a message behind the head' do
    it 'drops only that message, without republishing it' do
      result = discard('C')

      expect(result).to have_attributes(
        status: :success, message_id: 'C', found: true, outcome: nil,
        original_queue: 'billing.event.process', scanned: 3, truncated: false, error: nil,
      )
      expect(pops).to eq(%w[A B C])
      expect(broker.published).to be_empty
    end

    it 'leaves the other messages in the DLQ in their original order' do
      discard('C')

      expect(broker.ready_ids).to eq(%w[A B D E])
      expect(broker.channels.map(&:unacked)).to all(be_empty)
    end

    it 'commits the ack before writing the event' do
      discard('C')

      tx_at = broker.events.index([:tx_select])
      expect(broker.events.index([:nack, 'B'])).to be < tx_at
      expect(broker.events[tx_at..]).to eq([
        [:tx_select],
        [:ack, 'C'],
        [:tx_commit],
        [:audit, :success, { message_id: 'C', original_queue: 'billing.event.process' }],
        [:close],
      ])
    end

    it 'writes ONE fail-closed event: the message is gone and never mirrored' do
      discard('C', reason: 'poison message, ticket 77')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.discard', target: dlq, result: :success,
        detail: { message_id: 'C', original_queue: 'billing.event.process', reason: 'poison message, ticket 77' },
        fail_closed: true,
      )
    end
  end

  describe 'a message the scan does not see' do
    it 'is not_visible and drops nothing' do
      result = discard('missing')

      expect(result).to have_attributes(status: :not_visible, outcome: 'not_visible', found: false,
        original_queue: nil, scanned: 5, truncated: false)
      expect(broker.ready_ids).to eq(ids)
    end

    it 'records the attempt as not_visible on the operator trail, not fail-closed' do
      discard('missing')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor, verb: 'queue.dlq.discard', target: dlq, result: :success,
        detail: { message_id: 'missing', scanned: 5, truncated: false, outcome: 'not_visible' },
      )
    end

    it 'reports truncated when the scan stops at MAX_SCAN with messages behind it' do
      stub_const('Onetime::Operations::Dlq::Store::MAX_SCAN', 2)

      expect(discard('E')).to have_attributes(status: :not_visible, scanned: 2, truncated: true)
      expect(broker.ready_ids).to eq(ids)
    end

    it 'treats a queue that is not declared on the broker as not_visible' do
      undeclared = DlqFakeBroker.broker(ids, declared: false)

      expect(discard('C', conn: undeclared.connection))
        .to have_attributes(status: :not_visible, outcome: 'not_visible', scanned: 0)
    end
  end

  describe 'dry run' do
    it 'finds the message, drops nothing, and records one preview observation' do
      result = discard('C', dry_run: true)

      expect(result).to have_attributes(status: :dry_run, found: true, original_queue: 'billing.event.process')
      expect(broker.ready_ids).to eq(ids)
      expect(broker.events).not_to include([:ack, 'C'])
      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: actor, verb: 'queue.dlq.discard', target: dlq, result: 'preview',
        detail: { message_id: 'C', found: true, original_queue: 'billing.event.process', scanned: 3, dry_run: true },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'previews a miss as not_visible, still off the operator trail' do
      discard('missing', dry_run: true)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once
        .with(hash_including(detail: hash_including(found: false, outcome: 'not_visible')))
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'a drop the broker does not confirm' do
    let(:conn) do
      broker.connection { |ch| allow(ch).to receive(:tx_commit).and_raise(IOError, 'commit reply lost') }
    end

    it 'reports the outcome as unknown instead of discarded' do
      result = discard('C', conn: conn)

      expect(result).to have_attributes(status: :unconfirmed, outcome: 'unconfirmed', found: true)
      expect(result.error).to eq(
        'Discard outcome unknown: the broker did not confirm dropping this message ' \
        '(commit reply lost). It may still be in the DLQ.',
      )
    end

    it 'records one fail-closed failure event, since the message may be gone' do
      discard('C', conn: conn)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(result: :failure, fail_closed: true,
          detail: hash_including(message_id: 'C', outcome: 'unconfirmed')),
      )
    end

    it 'leaves the message in the DLQ when the commit never applied' do
      discard('C', conn: conn)

      expect(broker.ready_ids).to eq(ids)
    end
  end

  it 'records a broker failure as one failure event and re-raises' do
    conn = broker.connection { |ch| allow(ch).to receive(:queue).and_raise(IOError, 'broker gone') }

    expect { discard('C', conn: conn) }.to raise_error(IOError, 'broker gone')
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(verb: 'queue.dlq.discard', result: :failure,
        detail: hash_including(dry_run: false, message_id: 'C')),
    )
  end

  it 'refuses a blank message id' do
    expect { described_class.new(connection: connection, queue: dlq, message_id: '', actor: actor) }
      .to raise_error(ArgumentError, /message_id/)
  end
end
