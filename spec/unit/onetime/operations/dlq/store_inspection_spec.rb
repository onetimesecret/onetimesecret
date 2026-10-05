# spec/unit/onetime/operations/dlq/store_inspection_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Dlq::Store#peek / #find_message traversal (#4650).
#
# store_peek_spec stubs pops in sequence, so it cannot see a scan that keeps
# re-reading the head. The fake broker below keeps that state: a nack-requeued
# message goes back to the head, and a manual-ack delivery stays out of the
# queue until it is nacked or its channel closes. The live-broker version of
# these checks is spec/integration/all/jobs/dlq_inspection_spec.rb.

require 'spec_helper'
require 'onetime/operations/dlq/store'

RSpec.describe Onetime::Operations::Dlq::Store do
  # Unlike sequential pop stubs, this fake returns requeued messages to the head
  # and keeps manual-ack deliveries unavailable until nack or channel closure.
  let(:broker_class) do
    Class.new do
      attr_reader :ready, :unacked, :events

      def initialize(messages)
        @ready    = messages.dup
        @unacked  = {}
        @events   = []
        @next_tag = 0
        @open     = true
      end

      def queue(_name, durable:, passive:)
        raise 'inspection must use a passive durable queue' unless durable && passive

        self
      end

      def pop(manual_ack:)
        raise 'inspection must not auto-ack' unless manual_ack

        message = ready.shift
        return [nil, nil, nil] unless message

        tag          = @next_tag += 1
        unacked[tag] = message
        events << [:pop, JSON.parse(message[1]).fetch('id')]
        [Struct.new(:delivery_tag).new(tag), *message]
      end

      def nack(tag, multiple, requeue)
        raise 'inspection must requeue individual deliveries' if multiple || !requeue

        message = unacked.delete(tag) { raise 'unknown delivery tag' }
        ready.unshift(message)
        events << [:nack, JSON.parse(message[1]).fetch('id')]
      end

      def open?
        @open
      end

      def close
        unacked.keys.reverse_each { |tag| ready.unshift(unacked.delete(tag)) }
        @open = false
        events << [:close]
      end
    end
  end

  let(:dlq_name) { 'dlq.billing.event' }
  let(:properties) do
    %w[A B C].map do |id|
      double("properties-#{id}", message_id: id, headers: {}, timestamp: nil, content_type: 'application/json')
    end
  end
  let(:broker) do
    broker_class.new(properties.map { |props| [props, JSON.generate(id: props.message_id)] })
  end

  def expect_all_messages_returned
    expect(broker.ready.map { |props, _| props.message_id }).to contain_exactly('A', 'B', 'C')
    expect(broker.unacked).to be_empty
  end

  it 'visits three distinct messages before requeueing any delivery' do
    result = described_class.peek(broker, dlq_name, 3)

    expect(result.map { |message| message[:message_id] }).to eq(%w[A B C])
    expect(broker.events).to eq([[:pop, 'A'], [:pop, 'B'], [:pop, 'C'], [:nack, 'A'], [:nack, 'B'], [:nack, 'C']])
    expect_all_messages_returned
  end

  it 'finds a non-head message ID and requeues the entire scanned prefix' do
    result = described_class.find_message(broker, dlq_name, 'B', nil, 3)

    expect(result[:message_id]).to eq('B')
    expect(result[:payload]).to eq('id' => 'B')
    expect(broker.events).to eq([[:pop, 'A'], [:pop, 'B'], [:nack, 'A'], [:nack, 'B']])
    expect_all_messages_returned
  end

  it 'resolves a 1-based index to the second distinct message' do
    result = described_class.find_message(broker, dlq_name, nil, 2, 3)

    expect(result[:message_id]).to eq('B')
    expect_all_messages_returned
  end

  it 'returns nil for an absent ID after scanning every message once' do
    expect(described_class.find_message(broker, dlq_name, 'missing', nil, 3)).to be_nil
    expect(broker.events.select { |event| event.first == :pop }).to eq([[:pop, 'A'], [:pop, 'B'], [:pop, 'C']])
    expect_all_messages_returned
  end

  [:peek, :find_message].each do |operation|
    context operation.to_s do
      subject(:inspect_messages) do
        if operation == :peek
          described_class.peek(broker, dlq_name, 5)
        else
          described_class.find_message(broker, dlq_name, 'missing', nil, 5)
        end
      end

      it 'stops on an empty pop and returns every scanned delivery' do
        inspect_messages

        expect(broker.events.count { |event| event.first == :pop }).to eq(3)
        expect(broker.events.count { |event| event.first == :nack }).to eq(3)
        expect_all_messages_returned
      end

      it 'returns earlier deliveries when a subsequent pop raises' do
        pops = 0
        allow(broker).to receive(:pop).and_wrap_original do |original, **args|
          pops += 1
          raise 'pop failed' if pops == 3

          original.call(**args)
        end

        expect { inspect_messages }.to raise_error('pop failed')
        expect(broker.events).to eq([[:pop, 'A'], [:pop, 'B'], [:nack, 'A'], [:nack, 'B']])
        expect_all_messages_returned
      end

      it 'returns all held deliveries when reading properties raises' do
        broker
        method = operation == :peek ? :headers : :message_id
        allow(properties[1]).to receive(method).and_raise('projection failed')

        expect { inspect_messages }.to raise_error('projection failed')
        allow(properties[1]).to receive(method).and_return(method == :headers ? {} : 'B')
        expect(broker.events).to eq([[:pop, 'A'], [:pop, 'B'], [:nack, 'A'], [:nack, 'B']])
        expect_all_messages_returned
      end

      [1, 2].each do |failed_tag|
        it "closes the channel to return outstanding deliveries when nack #{failed_tag} fails" do
          allow(broker).to receive(:nack).and_wrap_original do |original, tag, multiple, requeue|
            raise 'nack failed' if tag == failed_tag

            original.call(tag, multiple, requeue)
          end

          expect { inspect_messages }.to raise_error('nack failed')
          expect(broker).not_to be_open
          expect_all_messages_returned
        end
      end

      it 'propagates channel closure errors if the requeue fallback fails' do
        allow(broker).to receive(:nack).and_raise('nack failed')
        allow(broker).to receive(:close).and_raise('close failed')

        expect { inspect_messages }.to raise_error('close failed')
        expect(broker).to have_received(:close).once
      end

      it 'does not close an already closed channel on a nack failure' do
        allow(broker).to receive(:nack) do
          broker.close
          raise 'channel closed'
        end
        allow(broker).to receive(:close).and_call_original

        expect { inspect_messages }.to raise_error('channel closed')
        expect(broker).to have_received(:close).once
        expect_all_messages_returned
      end
    end
  end

  it 'returns all held deliveries when building matched message detail raises' do
    allow(described_class).to receive(:build_message_detail).and_raise('detail failed')

    expect { described_class.find_message(broker, dlq_name, 'B', nil, 3) }.to raise_error('detail failed')
    expect(broker.events).to eq([[:pop, 'A'], [:pop, 'B'], [:nack, 'A'], [:nack, 'B']])
    expect_all_messages_returned
  end
end
