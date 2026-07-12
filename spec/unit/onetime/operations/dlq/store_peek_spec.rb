# spec/unit/onetime/operations/dlq/store_peek_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Dlq::Store#peek — non-consuming contract.
#
# Review gap "@claude #15" originally asked for GetDlqMessages broker-disconnect
# tests on the premise that a peek can LOSE messages if the broker drops. That
# premise is wrong: under AMQP a manual-ack delivery that is never acked/nacked
# is auto-requeued by the broker when the channel closes — nothing is lost. So
# rather than a flaky connection-drop simulation, these specs assert the real,
# app-observable guarantee that makes peek safe:
#
#   peek is READ-ONLY. Every message it pops is popped with a MANUAL ack and
#   immediately nack-requeued (requeue: true), so the queue is left exactly as
#   found — even when projecting a message raises mid-loop.
#
# Pure unit test: the Bunny channel/queue are mocked (no live RabbitMQ). The
# doubles mirror the shapes exercised by the live-broker specs in
# spec/integration/all/jobs/dlq_routing_spec.rb (delivery_info.delivery_tag,
# properties.headers/message_id/timestamp/content_type).

require 'spec_helper'
require 'onetime/operations/dlq/store'

RSpec.describe Onetime::Operations::Dlq::Store do
  subject(:peek) { described_class.peek(channel, dlq_name, count) }

  let(:dlq_name) { 'dlq.billing.event' }
  let(:count)    { messages.size }

  let(:channel) { instance_double('Bunny::Channel') }
  let(:queue)   { instance_double('Bunny::Queue') }

  # Build one AMQP delivery tuple (delivery_info, properties, payload) the way
  # Bunny::Queue#pop(manual_ack: true) returns it.
  def delivery(tag:, message_id: SecureRandom.uuid, payload: '{"data":"x"}')
    delivery_info = double("delivery_info-#{tag}", delivery_tag: tag)
    properties = double(
      "properties-#{tag}",
      headers: {
        'x-death' => [{ 'queue' => 'billing.event', 'reason' => 'rejected', 'count' => 1 }],
        'x-exception' => 'boom',
      },
      message_id: message_id,
      timestamp: Time.now,
      content_type: 'application/json',
    )
    [delivery_info, properties, payload]
  end

  # Default: two distinct messages, each popped once then requeued.
  let(:messages) do
    [
      delivery(tag: 'tag-1', message_id: 'msg-1', payload: '{"data":"one"}'),
      delivery(tag: 'tag-2', message_id: 'msg-2', payload: '{"data":"two"}'),
    ]
  end

  before do
    # queue_handle(channel, dlq_name) opens a passive, durable handle.
    allow(channel).to receive(:queue)
      .with(dlq_name, durable: true, passive: true)
      .and_return(queue)

    # Successive pops drain the fixture; the loop is bounded by `count` so it
    # never reads past the supplied deliveries.
    allow(queue).to receive(:pop).and_return(*messages)

    allow(channel).to receive(:nack)
  end

  # --------------------------------------------------------------------------
  # Contract 1: pops with a MANUAL ack (not auto-ack).
  # A manual-ack pop is the precondition for requeueing — an auto-ack pop would
  # consume the message the instant it is read.
  # --------------------------------------------------------------------------
  it 'pops each message with manual_ack: true (never auto-ack)' do
    peek

    expect(queue).to have_received(:pop).with(manual_ack: true).exactly(count).times
  end

  # --------------------------------------------------------------------------
  # Contract 2 (load-bearing): every popped message is nack-requeued.
  # The third arg to channel.nack is requeue — `true` puts the message straight
  # back on the queue, which is what makes the peek non-consuming.
  # --------------------------------------------------------------------------
  it 'nacks every popped message with requeue: true (the non-consuming guarantee)' do
    peek

    expect(channel).to have_received(:nack).with('tag-1', false, true)
    expect(channel).to have_received(:nack).with('tag-2', false, true)
    expect(channel).to have_received(:nack).exactly(count).times
  end

  it 'requeues exactly the messages it read — no message left un-nacked' do
    peek

    # One pop, one requeue, per message: reads == requeues means the queue depth
    # is conserved across the peek.
    expect(channel).to have_received(:nack).exactly(count).times
  end

  # --------------------------------------------------------------------------
  # Contract 3: the requeue is in an `ensure`, so a projection error mid-loop
  # must NOT strand the popped message un-requeued.
  # --------------------------------------------------------------------------
  context 'when projecting a message raises' do
    let(:messages) { [delivery(tag: 'tag-1', message_id: 'msg-1')] }

    before do
      # Force the body block to blow up AFTER the manual-ack pop but BEFORE the
      # ensure. properties.headers is the first thing the body touches.
      _di, properties, _payload = messages.first
      allow(properties).to receive(:headers).and_raise(StandardError, 'projection blew up')
    end

    it 'still nack-requeues the popped message before propagating (ensure runs)' do
      expect { peek }.to raise_error(StandardError, 'projection blew up')

      expect(channel).to have_received(:nack).with('tag-1', false, true)
    end
  end

  # --------------------------------------------------------------------------
  # Contract 4: peek returns the decoded projection for each message — a read
  # that yields data, without consuming.
  # --------------------------------------------------------------------------
  it 'returns one decoded summary per message without consuming them' do
    result = peek

    expect(result.size).to eq(count)
    expect(result.map { |m| m[:message_id] }).to eq(%w[msg-1 msg-2])
    expect(result.map { |m| m[:payload_preview] }).to eq(['{"data":"one"}', '{"data":"two"}'])
    # x-death header survives the projection.
    expect(result.map { |m| m[:original_queue] }).to all(eq('billing.event'))
    expect(result.map { |m| m[:death_reason] }).to all(eq('rejected'))
  end

  # --------------------------------------------------------------------------
  # Bounded: an empty pop (nil delivery_info) breaks the loop — peek never
  # spins past the messages the queue actually holds.
  # --------------------------------------------------------------------------
  context 'when the queue drains before count is reached' do
    let(:count) { 5 }

    before do
      # One real message, then the broker returns an empty pop.
      allow(queue).to receive(:pop).and_return(delivery(tag: 'tag-1', message_id: 'msg-1'), nil)
    end

    it 'stops at the empty pop and only requeues what it read' do
      result = peek

      expect(result.size).to eq(1)
      expect(channel).to have_received(:nack).with('tag-1', false, true).once
      expect(channel).to have_received(:nack).once
    end
  end
end
