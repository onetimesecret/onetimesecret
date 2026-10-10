# spec/unit/onetime/operations/dlq/replay_unroutable_spec.rb
#
# frozen_string_literal: true

# Bulk Onetime::Operations::Dlq::Replay when a message's original queue does
# not exist (#4343 review R1-4).
#
# A default-exchange publish to a queue that does not exist is accepted and
# dropped by the broker. Committed together with the DLQ ack, that loses the
# message while the replay counts it as replayed. The replay now checks the
# queue first (passive declare on a probe channel) and publishes `mandatory`,
# putting a returned copy back in the DLQ. The per-message path is covered in
# replay_message_spec.rb; the real-broker check is in
# spec/integration/all/jobs/dlq_message_ops_spec.rb.

require 'spec_helper'
require 'onetime/operations/dlq/replay'

RSpec.describe Onetime::Operations::Dlq::Replay, 'with a missing original queue' do
  let(:actor) { 'ur_colonel_public' }
  let(:dlq) { 'dlq.billing.event' }
  let(:broker) do
    DlqFakeBroker::Broker.new(
      [
        DlqFakeBroker.message('A'),
        DlqFakeBroker.message('B', original_queue: 'gone.queue'),
        DlqFakeBroker.message('C'),
        DlqFakeBroker.message('D', original_queue: 'gone.queue'),
      ],
      name: dlq,
    )
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    broker.missing_queues << 'gone.queue'
  end

  def replay = described_class.new(connection: broker.connection, queue: dlq, actor: actor).call

  it 'replays the routable messages and counts the others as failed' do
    result = replay

    expect(result).to have_attributes(status: :success, replayed: 2, failed: 2)
    expect(broker.published.map { |entry| entry[:opts][:message_id] }).to eq(%w[A C])
    expect(result.errors.map { |error| error[:message_id] }).to eq(%w[B D])
    expect(result.errors.first[:error]).to include('no queue named gone.queue')
  end

  it 'leaves the unroutable messages in the DLQ in their order, never published or dropped' do
    replay

    expect(broker.ready_ids).to eq(%w[B D])
    expect(broker.events).not_to include(a_collection_including(:dropped_unroutable))
  end

  it 'checks a missing queue once per run' do
    replay

    expect(broker.events.count([:probe, 'gone.queue'])).to eq(1)
    expect(broker.events.count([:probe, 'billing.event.process'])).to eq(2)
  end

  it 'publishes mandatory, so a queue deleted after the check returns the copy' do
    replay

    expect(broker.published.map { |entry| entry[:opts][:mandatory] }).to all(be(true))
  end

  it 'puts a copy returned after the check back at the end of the DLQ and carries on' do
    broker.missing_queues.clear
    commits = 0
    broker.before_commit = lambda do
      commits += 1
      broker.missing_queues << 'billing.event.process' if commits == 1
    end

    result = replay

    expect(broker.events).to include([:returned, 'A', 'billing.event.process'], [:enqueued, 'A'])
    # A came back and was put at the end; the rest of the batch still ran
    # (C's queue is now remembered as missing, so it stays too).
    expect(result).to have_attributes(replayed: 2, failed: 2)
    expect(broker.ready_ids).to eq(%w[C A])
  end

  it 'stops the batch when putting a returned copy back fails' do
    broker.missing_queues.clear
    commits = 0
    broker.before_commit = lambda do
      commits += 1
      broker.missing_queues << 'billing.event.process' if commits == 1
      raise IOError, 'commit reply lost' if commits == 2
    end

    result = replay

    expect(result).to have_attributes(replayed: 0, failed: 1)
    expect(result.errors.first[:error]).to include('the message may be lost')
    expect(broker.events.count { |event| event.first == :pop }).to eq(1)
  end

  it 'keeps the single applied event and its counts' do
    replay

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: actor, verb: 'queue.dlq.replay', target: dlq, result: :success,
      detail: { replayed: 2, failed: 2 },
    )
  end
end
