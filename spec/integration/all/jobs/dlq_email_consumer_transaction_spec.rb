# spec/integration/all/jobs/dlq_email_consumer_transaction_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob against a real RabbitMQ broker: the replay publish is
# committed first, and the DLQ ack is committed only when the broker did not
# return the publish as unroutable. Failures are injected after the publish
# or ack frame has been written, to check what the broker holds afterwards
# in the target queue and in the DLQ.
#
# The replay reservation (Valkey) is stubbed; these examples cover only the
# AMQP side. The double-based unit spec for the same paths is
# spec/unit/onetime/jobs/scheduled/dlq_email_consumer_job_spec.rb.
#
# Requires the lane's test broker on 127.0.0.1:2156 (tests/lanes/README.md,
# Service safety boundary). Run through the lane runner:
#   tests/lanes/run simple --only spec/integration/all/jobs/dlq_email_consumer_transaction_spec.rb

require 'spec_helper'
require 'bunny'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob, :rabbitmq, type: :integration do
  let(:logger) { double('logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:payload) { JSON.generate('raw' => true, 'email' => { 'to' => 'test@example.com' }) }
  let(:connection) do
    url = ENV.fetch('RABBITMQ_URL')
    uri = URI.parse(url)
    unless uri.host == '127.0.0.1' && uri.port == 2156
      raise "Refusing to run against #{uri.host}:#{uri.port}; expected the lane test broker on 127.0.0.1:2156"
    end

    Bunny.new(url, automatically_recover: false, connection_timeout: 5, read_timeout: 5).tap(&:start)
  end
  let(:channel) { connection.create_channel }
  let(:observer) { connection.create_channel }
  let(:suffix) { SecureRandom.hex(12) }
  let(:dlq_name) { "test.dlq-consumer.dlq.#{suffix}" }
  let(:target_name) { "test.dlq-consumer.target.#{suffix}" }
  let(:queue) { observer.queue(dlq_name, durable: true) }
  let(:target) { observer.queue(target_name, durable: true) }
  let(:message_id) { "test-dlq-consumer-#{suffix}" }

  def run_batch
    described_class.send(:consume_dlq_batch)
  end

  # Dead-letter a message into the test DLQ, routed back to the test target.
  def dead_letter(id, body = payload)
    queue.publish(body, persistent: true, message_id: id, content_type: 'application/json',
      headers: { 'x-death' => [{ 'queue' => target_name }], 'x-schema-version' => 1 })
    observer.queue(dlq_name, passive: true) # synchronous barrier after the publish
  end

  before do
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    allow(described_class).to receive(:reserve_replay).and_return(1)
    allow(described_class).to receive(:start_replay).and_return(true)
    allow(described_class).to receive(:finalize_replay)
    allow(described_class).to receive(:release_reservation)
    allow(described_class).to receive(:acquire_channel).and_return([nil, channel, false])
    stub_const("#{described_class.name}::DLQ_NAME", dlq_name)
    target
    dead_letter(message_id)
  end

  after do
    if connection.open?
      observer.queue_delete(dlq_name)
      observer.queue_delete(target_name)
      connection.close
    end
  end

  it 'leaves one copy after an interrupted ack: the next run acks the delivery without publishing' do
    allow(channel).to receive(:ack) do
      # The publish is committed and its copy is live. Closing the channel
      # before the ack returns the DLQ delivery to the DLQ.
      channel.close
      raise IOError, 'channel closed before ack'
    end
    run_batch
    expect(described_class).to have_received(:finalize_replay).with(message_id, anything, anything).once
    expect(described_class).not_to have_received(:release_reservation)
    expect(queue.message_count).to eq(1)
    expect(target.message_count).to eq(1)

    # finalize_replay marked the id completed, which the next run reads.
    allow(described_class).to receive(:reserve_replay).and_return(2)
    allow(described_class).to receive(:acquire_channel).and_return([nil, connection.create_channel, false])
    run_batch
    expect(queue.message_count).to eq(0)
    expect(target.message_count).to eq(1)
    _, metadata, body = target.pop
    expect(metadata.message_id).to eq(message_id)
    expect(metadata.headers).to eq('x-schema-version' => 1)
    expect(body).to eq(payload)
  end

  it 'rolls back a written publish before the next message commits on an open channel' do
    dead_letter("#{message_id}-second")
    calls = 0
    allow(channel.default_exchange).to receive(:publish).and_wrap_original do |operation, *args, **kwargs|
      operation.call(*args, **kwargs)
      calls += 1
      raise IOError, 'publish interrupted after write' if calls == 1
    end
    run_batch
    expect(target.message_count).to eq(1)
    expect(queue.message_count).to eq(1)
    expect(queue.pop[1].message_id).to eq(message_id)
    expect(target.pop[1].message_id).to eq("#{message_id}-second")
  end

  it 'keeps a replay whose original queue does not exist, and replays it once the queue exists' do
    queue.purge
    missing_name = "test.dlq-consumer.missing.#{suffix}"
    missing_id   = "#{message_id}-unroutable"
    headers      = { 'x-death' => [{ 'queue' => missing_name }], 'x-schema-version' => 1 }
    queue.publish(payload, persistent: true, message_id: missing_id,
      content_type: 'application/json', headers: headers)
    dead_letter(message_id)

    run_batch

    # The message behind the unroutable one is replayed in the same batch.
    expect(target.message_count).to eq(1)
    expect(target.pop[1].message_id).to eq(message_id)
    expect(queue.message_count).to eq(1)
    expect(logger).to have_received(:error).with(
      "[DlqEmailConsumerJob] Replay unroutable: no queue named #{missing_name}; left in the DLQ",
      message_id: missing_id,
    ).once
    expect(logger).to have_received(:info).with(/replayed=1 .*deferred=1 unroutable=1/)
    expect(described_class).to have_received(:release_reservation)
      .with(missing_id, anything, include_publishing: true).once
    expect(described_class).to have_received(:finalize_replay).with(message_id, anything, anything).once
    expect(described_class).not_to have_received(:finalize_replay).with(missing_id, anything, anything)

    missing = observer.queue(missing_name, durable: true)
    begin
      allow(described_class).to receive(:acquire_channel).and_return([nil, connection.create_channel, false])
      run_batch
      expect(queue.message_count).to eq(0)
      expect(missing.message_count).to eq(1)
      _, metadata, body = missing.pop
      expect(metadata.message_id).to eq(missing_id)
      expect(metadata.headers).to eq('x-schema-version' => 1)
      expect(body).to eq(payload)
    ensure
      observer.queue_delete(missing_name)
    end
  end

  it 'defers malformed x-death metadata without leaking frames into the next replay commit' do
    queue.purge
    poison_id = "#{message_id}-poison"
    poison_headers = { 'x-death' => ['not-a-death-table'], 'x-schema-version' => 1 }
    queue.publish(payload, persistent: true, message_id: poison_id,
      content_type: 'application/json', headers: poison_headers)
    dead_letter(message_id)

    exchange = channel.default_exchange
    allow(exchange).to receive(:publish).and_call_original
    [:ack, :nack, :reject, :tx_commit, :tx_rollback].each do |operation|
      allow(channel).to receive(operation).and_call_original
    end

    deliveries = {}
    allow(described_class).to receive(:process_message).and_wrap_original do |process, *args|
      _, delivery_info, properties, _, results = args
      deliveries[properties.message_id] = delivery_info.delivery_tag
      process.call(*args)

      if properties.message_id == poison_id
        expect(results).to include(errors: 1, deferred: 1, replayed: 0)
        expect(channel).to be_open
        expect(exchange).not_to have_received(:publish)
        [:ack, :nack, :reject, :tx_commit, :tx_rollback].each do |operation|
          expect(channel).not_to have_received(operation)
        end
        expect(described_class).not_to have_received(:reserve_replay)
      end
    end

    run_batch

    expect(deliveries.keys).to eq([poison_id, message_id])
    expect(logger).to have_received(:error).with(
      '[DlqEmailConsumerJob] Processing deferred: NoMethodError',
    ).once
    expect(exchange).to have_received(:publish).with(payload,
      routing_key: target_name, mandatory: true, persistent: true, message_id: message_id,
      content_type: 'application/json', headers: { 'x-schema-version' => 1 }).once
    expect(channel).to have_received(:ack).with(deliveries.fetch(message_id)).once
    expect(channel).not_to have_received(:ack).with(deliveries.fetch(poison_id))
    expect(channel).not_to have_received(:nack)
    expect(channel).not_to have_received(:reject)
    expect(channel).not_to have_received(:tx_rollback)
    expect(channel).to have_received(:tx_commit).twice

    expect(queue.message_count).to eq(1)
    expect(target.message_count).to eq(1)
    _, retained_properties, retained_body = queue.pop
    expect(retained_properties.message_id).to eq(poison_id)
    expect(retained_properties.headers).to eq(poison_headers)
    expect(retained_body).to eq(payload)
    _, replayed_properties, replayed_body = target.pop
    expect(replayed_properties.message_id).to eq(message_id)
    expect(replayed_properties.headers).to eq('x-schema-version' => 1)
    expect(replayed_body).to eq(payload)
  end

  it 'stops when the commit cannot be sent, without settling either DLQ delivery' do
    dead_letter("#{message_id}-second")
    allow(channel).to receive(:tx_commit).and_raise(IOError, 'commit write interrupted')
    expect(channel).not_to receive(:tx_rollback)
    run_batch
    expect(target.message_count).to eq(0)
    expect(queue.message_count).to eq(2)
  end

  it 'stops after a publish commit the broker applied but whose confirmation is lost' do
    dead_letter("#{message_id}-second")
    allow(channel).to receive(:tx_commit).and_wrap_original do |commit|
      commit.call
      raise IOError, 'commit confirmation lost'
    end
    run_batch
    # The copy is live and neither delivery was acked. The first stays
    # behind its publishing reservation until that expires.
    expect(target.message_count).to eq(1)
    expect(queue.message_count).to eq(2)
    expect(described_class).not_to have_received(:release_reservation)
    expect(described_class).not_to have_received(:finalize_replay)
  end

  it 'commits a message without an id followed by a non-auth discard' do
    # A message without an id takes no replay reservation.
    queue.publish(payload, persistent: true, content_type: 'application/json',
      headers: { 'x-death' => [{ 'queue' => target_name }] })
    queue.publish(JSON.generate('template' => 'secret_link'), persistent: true)
    observer.queue(dlq_name, passive: true)
    run_batch
    expect(queue.message_count).to eq(0)
    expect(target.message_count).to eq(2)
  end
end
