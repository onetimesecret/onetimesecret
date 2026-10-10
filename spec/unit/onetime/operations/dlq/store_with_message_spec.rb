# spec/unit/onetime/operations/dlq/store_with_message_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Dlq::Store.with_message — the bounded, hold-and-yield
# lookup behind the per-message DLQ verbs (#4343).
#
# Uses the stateful fake in spec/support/fake_dlq_broker.rb: a requeued
# delivery returns to its original position, so a scan that nack-requeued each
# non-match at once would pop the head again (#4650) and these examples would
# see it. The live-broker version is
# spec/integration/all/jobs/dlq_message_ops_spec.rb.

require 'spec_helper'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/peek'

RSpec.describe Onetime::Operations::Dlq::Store, '.with_message' do
  let(:dlq_name) { 'dlq.billing.event' }
  let(:broker) { DlqFakeBroker.broker(%w[A B C D E]) }
  let(:channel) { broker.connection.create_channel }

  def pops = broker.events.select { |event| event.first == :pop }.map(&:last)

  it 'reaches a non-head message without popping any message twice' do
    scan = described_class.with_message(channel, dlq_name, 'C') { |_, properties, _| properties.message_id }

    expect(scan).to have_attributes(found: true, scanned: 3, truncated: false, value: 'C')
    expect(pops).to eq(%w[A B C])
  end

  it 'returns the messages ahead of the match before the block runs' do
    seen = nil
    described_class.with_message(channel, dlq_name, 'C') do |*|
      seen = { ready: broker.ready_ids, unacked: channel.unacked.values.map(&:id) }
    end

    # Only the match is still held; the prefix is back in front of D and E.
    expect(seen).to eq(ready: %w[A B D E], unacked: %w[C])
  end

  it 'leaves the queue in its original order once the caller closes the channel' do
    described_class.with_message(channel, dlq_name, 'C') { |*| nil }
    channel.close

    expect(broker.ready_ids).to eq(%w[A B C D E])
  end

  it 'lets the block settle the match without touching the others' do
    described_class.with_message(channel, dlq_name, 'C') do |delivery_info, _, _|
      channel.ack(delivery_info.delivery_tag)
    end
    channel.close

    expect(broker.ready_ids).to eq(%w[A B D E])
  end

  it 'reports a miss after scanning every visible message once, block not called' do
    called = false
    scan   = described_class.with_message(channel, dlq_name, 'missing') { called = true }

    expect(scan).to have_attributes(found: false, scanned: 5, truncated: false, value: nil)
    expect(called).to be(false)
    expect(pops).to eq(%w[A B C D E])
    expect(broker.ready_ids).to eq(%w[A B C D E])
  end

  describe 'the scan bound' do
    it 'stops at max_scan and reports truncated while messages remain behind' do
      scan = described_class.with_message(channel, dlq_name, 'E', max_scan: 2) { |*| :unreached }

      expect(scan).to have_attributes(found: false, scanned: 2, truncated: true, value: nil)
      expect(pops).to eq(%w[A B])
      expect(broker.ready_ids).to eq(%w[A B C D E])
    end

    it 'is not truncated when the bound equals the queue depth' do
      scan = described_class.with_message(channel, dlq_name, 'missing', max_scan: 5) { |*| nil }

      expect(scan).to have_attributes(found: false, scanned: 5, truncated: false)
    end

    it 'defaults to MAX_SCAN, the bound every request-path lookup uses' do
      stub_const("#{described_class}::MAX_SCAN", 3)

      scan = described_class.with_message(channel, dlq_name, 'missing') { |*| nil }

      expect(scan).to have_attributes(scanned: 3, truncated: true)
    end

    it 'honours a larger explicit bound (the CLI --max-scan)' do
      stub_const("#{described_class}::MAX_SCAN", 3)

      scan = described_class.with_message(channel, dlq_name, 'E', max_scan: 10) { |*| :found }

      expect(scan).to have_attributes(found: true, scanned: 5, value: :found)
    end

    it 'refuses a bound that is not a positive integer, before popping' do
      [0, -1, nil, 'many'].each do |bound|
        expect { described_class.with_message(channel, dlq_name, 'A', max_scan: bound) { |*| nil } }
          .to raise_error(ArgumentError, /max_scan/)
      end
      expect(pops).to be_empty
    end

    it 'keeps MAX_SCAN within the ledger ceiling and above the peek window' do
      expect(described_class::MAX_SCAN).to be_between(Onetime::Operations::Dlq::Peek::MAX_LIMIT, 1000)
    end
  end

  it 'refuses a blank message id, which would match any message without one' do
    expect { described_class.with_message(channel, dlq_name, '') { |*| nil } }
      .to raise_error(ArgumentError, /message_id/)
    expect(pops).to be_empty
  end

  it 'returns the scanned prefix when a later pop raises' do
    handle = channel.queue(dlq_name, durable: true, passive: true)
    allow(channel).to receive(:queue).and_return(handle)
    pops_seen = 0
    allow(handle).to receive(:pop).and_wrap_original do |original, **args|
      pops_seen += 1
      raise 'pop failed' if pops_seen == 3

      original.call(**args)
    end

    expect { described_class.with_message(channel, dlq_name, 'E') { |*| nil } }.to raise_error('pop failed')
    expect(broker.ready_ids).to eq(%w[A B C D E])
  end

  it 'has already returned the prefix when the block raises; the match returns on close' do
    expect { described_class.with_message(channel, dlq_name, 'C') { |*| raise 'settle failed' } }
      .to raise_error('settle failed')
    expect(broker.ready_ids).to eq(%w[A B D E])

    channel.close
    expect(broker.ready_ids).to eq(%w[A B C D E])
  end

  it 'propagates Bunny::NotFound for an undeclared queue without popping' do
    undeclared = DlqFakeBroker.broker(%w[A], declared: false)

    expect { described_class.with_message(undeclared.connection.create_channel, dlq_name, 'A') { |*| nil } }
      .to raise_error(Bunny::NotFound)
    expect(undeclared.events).to be_empty
  end
end
