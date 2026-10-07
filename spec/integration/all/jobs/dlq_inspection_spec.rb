# spec/integration/all/jobs/dlq_inspection_spec.rb
#
# frozen_string_literal: true

# DLQ inspection traversal against a real broker (#4650).
#
# Onetime::Operations::Dlq::Store#peek and #find_message must visit distinct
# messages and leave every message on the queue. The unit fake in
# spec/unit/onetime/operations/dlq/store_inspection_spec.rb models the broker;
# these examples check the same behavior on RabbitMQ.
#
# Requirements: the lane runner's test broker (RABBITMQ_URL on 127.0.0.1:2156).
# Unlike the sibling RabbitMQ specs, this file does not skip when the broker is
# missing: it fails, so a lane cannot pass without running it.

require 'spec_helper'
require 'bunny'
require 'uri'
require 'timeout'
require 'onetime/operations/dlq/store'

RSpec.describe 'DLQ inspection traversal', :rabbitmq, type: :integration do
  let(:store) { Onetime::Operations::Dlq::Store }
  let(:queue_name) { "test.dlq.inspection.#{SecureRandom.uuid}" }
  let(:connection) do
    url = ENV.fetch('RABBITMQ_URL')
    uri = URI.parse(url)
    raise 'DLQ regression requires the isolated test broker' unless uri.host == '127.0.0.1' && uri.port == 2156

    Bunny.new(url, automatically_recover: false, connection_timeout: 5, read_timeout: 5).tap(&:start)
  end
  let(:channel) { connection.create_channel }
  let(:queue) { channel.queue(queue_name, durable: true, exclusive: true, auto_delete: true) }

  before do
    queue
    channel.confirm_select
    %w[A B C].each do |id|
      channel.default_exchange.publish(JSON.generate(id: id), routing_key: queue_name, message_id: id, content_type: 'application/json')
    end
    raise 'test publishes were not confirmed' unless channel.wait_for_confirms
  end

  after do
    # The exclusive, uniquely named queue disappears with this test connection.
    connection.close if connection.open?
  end

  def expect_ready_depth(queue)
    # Nacks and broker-side channel-close requeues are asynchronous.
    Timeout.timeout(5) { sleep 0.01 until queue.message_count == 3 }
    expect(queue.message_count).to eq(3)
  end

  def expect_messages_preserved
    expect_ready_depth(queue)
    ids = Array.new(3) do
      delivery, properties, = queue.pop(manual_ack: true)
      expect(delivery).not_to be_nil
      properties.message_id
    end
    expect(ids).to contain_exactly('A', 'B', 'C')
    channel.close # Return verification deliveries; never ack inspection data.
  end

  it 'visits three distinct messages instead of repeatedly requeueing the head' do
    expect(store.peek(channel, queue_name, 3).map { |message| message[:message_id] }).to eq(%w[A B C])
    expect_messages_preserved
  end

  it 'finds a non-head message ID' do
    expect(store.find_message(channel, queue_name, 'B', nil, 3)&.fetch(:message_id)).to eq('B')
    expect_messages_preserved
  end

  it 'resolves a 1-based index to the second distinct message' do
    expect(store.find_message(channel, queue_name, nil, 2, 3)&.fetch(:message_id)).to eq('B')
    expect_messages_preserved
  end

  it 'preserves messages when detail projection raises after a scanned prefix' do
    allow(store).to receive(:build_message_detail).and_raise('detail failed')

    expect { store.find_message(channel, queue_name, 'B', nil, 3) }.to raise_error('detail failed')
    expect_messages_preserved
  end

  it 'preserves messages through channel closure when nack fails' do
    allow(channel).to receive(:nack).and_raise('nack failed')

    expect { store.peek(channel, queue_name, 3) }.to raise_error('nack failed')
    expect(channel).not_to be_open

    verification_channel = connection.create_channel
    verification_queue   = verification_channel.queue(queue_name, durable: true, passive: true)
    expect_ready_depth(verification_queue)

    ids = Array.new(3) { verification_queue.pop(manual_ack: true)[1].message_id }
    expect(ids).to contain_exactly('A', 'B', 'C')
    verification_channel.close
  end
end
