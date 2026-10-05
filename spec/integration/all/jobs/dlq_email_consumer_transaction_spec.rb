# spec/integration/all/jobs/dlq_email_consumer_transaction_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob against a real RabbitMQ broker: the replay publish and
# the DLQ ack are committed in one AMQP transaction. Failures are injected
# after the publish or ack frame has been written, to check what the broker
# holds afterwards in the target queue and in the DLQ.
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
require 'onetime/operations/dlq/replay'

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

  it 'leaves one copy after an interrupted publish/ack followed by an operator replay' do
    allow(channel).to receive(:ack) do
      # The publish frame is already written. Closing the channel before the
      # ack is the window in which, without a transaction, the copy is live
      # and the DLQ delivery returns to the DLQ.
      channel.close
      raise IOError, 'channel closed before ack'
    end
    batch_error = nil
    begin
      run_batch
    rescue StandardError => ex
      # Without the transaction, the job's nack on the closed channel raises
      # out of the batch. Record it and check the queues first.
      batch_error = ex
    end
    expect(queue.message_count).to eq(1)
    expect(target.message_count).to eq(0)

    op = Onetime::Operations::Dlq::Replay.new(connection: connection, queue: dlq_name, actor: 'test:dlq-consumer')
    expect(op).to receive(:release_processing_claim).with(message_id)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    result = op.call
    expect(result.replayed).to eq(1)
    expect(queue.message_count).to eq(0)
    expect(target.message_count).to eq(1)
    _, metadata, body = target.pop
    expect(metadata.message_id).to eq(message_id)
    expect(metadata.headers).to eq('x-schema-version' => 1)
    expect(body).to eq(payload)
    expect(batch_error).to be_nil
  end

  [:publish, :ack].each do |failure|
    it "rolls back a written #{failure} before the next message commits on an open channel" do
      dead_letter("#{message_id}-second")
      calls = 0
      transport = failure == :publish ? channel.default_exchange : channel
      allow(transport).to receive(failure).and_wrap_original do |operation, *args, **kwargs|
        operation.call(*args, **kwargs)
        calls += 1
        raise IOError, "#{failure} interrupted after write" if calls == 1
      end
      run_batch
      expect(target.message_count).to eq(1)
      expect(queue.message_count).to eq(1)
      expect(queue.pop[1].message_id).to eq(message_id)
      expect(target.pop[1].message_id).to eq("#{message_id}-second")
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
      routing_key: target_name, persistent: true, message_id: message_id,
      content_type: 'application/json', headers: { 'x-schema-version' => 1 }).once
    expect(channel).to have_received(:ack).with(deliveries.fetch(message_id)).once
    expect(channel).not_to have_received(:ack).with(deliveries.fetch(poison_id))
    expect(channel).not_to have_received(:nack)
    expect(channel).not_to have_received(:reject)
    expect(channel).not_to have_received(:tx_rollback)
    expect(channel).to have_received(:tx_commit).once

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

  it 'stops after a commit the broker applied but whose confirmation is lost' do
    dead_letter("#{message_id}-second")
    allow(channel).to receive(:tx_commit).and_wrap_original do |commit|
      commit.call
      raise IOError, 'commit confirmation lost'
    end
    run_batch
    expect(target.message_count).to eq(1)
    expect(queue.message_count).to eq(1)
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
