# spec/integration/all/jobs/dlq_email_consumer_recovery_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob against a real RabbitMQ broker and the test Valkey:
# a replay that fails or is not confirmed leaves the original in the DLQ,
# unacked until the job's channel closes, and a later run replays it instead
# of acking it as a duplicate. The replay reservation and completed marker
# are the job's real datastore keys.
#
# The double-based unit spec for the same paths is
# spec/unit/onetime/jobs/scheduled/dlq_email_consumer_job_spec.rb.
#
# Requires the lane's test broker on 127.0.0.1:2156 (tests/lanes/README.md,
# Service safety boundary). Run through the lane runner:
#   tests/lanes/run simple --only spec/integration/all/jobs/dlq_email_consumer_recovery_spec.rb

require 'spec_helper'
require 'bunny'
require 'securerandom'
require 'timeout'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob, :rabbitmq, type: :integration do
  let(:logger) { double('logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:redis) { Familia.dbclient }
  let(:payload) { JSON.generate('raw' => true, 'email' => { 'to' => 'test@example.com' }) }
  let(:results) { { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0, deferred: 0 } }
  let(:connection) do
    url = ENV.fetch('RABBITMQ_URL')
    uri = URI.parse(url)
    unless uri.host == '127.0.0.1' && uri.port == 2156
      raise "Refusing to run against #{uri.host}:#{uri.port}; expected the lane test broker on 127.0.0.1:2156"
    end

    Bunny.new(url, automatically_recover: false, connection_timeout: 5, read_timeout: 5).tap(&:start)
  end
  let(:broker_channel) { connection.create_channel }
  let(:suffix) { SecureRandom.hex(12) }
  let(:message_id) { "test-dlq-recovery-#{suffix}" }
  let(:dlq_name) { "test.dlq-recovery.dlq.#{suffix}" }
  let(:target_name) { "test.dlq-recovery.target.#{suffix}" }
  let(:dlq) { broker_channel.queue(dlq_name, durable: true) }
  let(:target) { broker_channel.queue(target_name, durable: true) }
  let(:completed_key) { "dlq:replayed:#{message_id}" }
  let(:reservation_key) { "dlq:replay:reservation:#{message_id}" }
  let(:worker_key) { Onetime::Jobs::QueueConfig.processing_claim_key(message_id) }

  # Dead-letter a copy of the message into the test DLQ, routed back to the
  # test target.
  def dead_letter
    broker_channel.default_exchange.publish(payload, routing_key: dlq_name, message_id: message_id,
      content_type: 'application/json', headers: { 'x-death' => [{ 'queue' => target_name }] })
  end

  # A closed channel's unacked deliveries return to the queue asynchronously.
  def await_dlq_depth(ch, depth)
    Timeout.timeout(5) { sleep 0.01 until ch.queue(dlq_name, durable: true).message_count == depth }
  end

  # One message on its own channel, in transaction mode as consume_dlq_batch
  # sets it up.
  def process_broker_message(ch)
    ch.tx_select
    info, props, body = ch.queue(dlq_name, durable: true).pop(manual_ack: true)
    expect(info).not_to be_nil
    described_class.send(:process_message, ch, info, props, body, results)
  end

  before do
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    stub_const("#{described_class.name}::DLQ_NAME", dlq_name)
    dlq
    target
    dead_letter
  end

  after do
    redis.del(completed_key, reservation_key, worker_key)
    if connection.open?
      cleanup = connection.create_channel
      cleanup.queue_delete(dlq_name)
      cleanup.queue_delete(target_name)
      cleanup.close
      connection.close
    end
  end

  it 'returns a failed publish to the DLQ on close and successfully replays it later' do
    allow(broker_channel.default_exchange).to receive(:publish).and_raise(IOError, 'publish failed before write')
    process_broker_message(broker_channel)
    expect(dlq.message_count).to eq(0) # Held unacked, not repeatedly popped.
    broker_channel.close

    # The rollback released the reservation, so the next run replays it.
    expect(redis.get(reservation_key)).to be_nil
    expect(redis.get(completed_key)).to be_nil
    retry_channel = connection.create_channel
    await_dlq_depth(retry_channel, 1)
    process_broker_message(retry_channel)
    expect(retry_channel.queue(target_name, durable: true).message_count).to eq(1)
    expect(retry_channel.queue(dlq_name, durable: true).message_count).to eq(0)
    expect(redis.get(completed_key)).to eq('completed')
    retry_channel.close
  end

  it 'recovers an original returned by a channel closing before publish' do
    allow(broker_channel.default_exchange).to receive(:publish) do
      broker_channel.close
      raise IOError, 'channel closed before publish'
    end
    expect { process_broker_message(broker_channel) }
      .to raise_error(described_class::BatchStopped, /rollback failed/i)
    expect(redis.get(completed_key)).to be_nil
    expect(redis.get(reservation_key)).to be_nil

    retry_channel = connection.create_channel
    await_dlq_depth(retry_channel, 1)
    process_broker_message(retry_channel)
    expect(retry_channel.queue(target_name, durable: true).message_count).to eq(1)
    expect(retry_channel.queue(dlq_name, durable: true).message_count).to eq(0)
    retry_channel.close
  end

  it 'keeps a replay whose commit was not applied, and replays it after the uncertainty window' do
    allow(broker_channel).to receive(:tx_commit).and_raise(IOError, 'commit write interrupted')
    expect { process_broker_message(broker_channel) }
      .to raise_error(described_class::BatchStopped, /outcome unknown/i)
    broker_channel.close
    expect(redis.get(reservation_key)).to start_with('publishing:')
    expect(redis.get(completed_key)).to be_nil

    # The next run finds the delivery back in the DLQ. It must not ack it
    # as already replayed: no copy reached the target queue.
    retry_channel = connection.create_channel
    await_dlq_depth(retry_channel, 1)
    process_broker_message(retry_channel)
    expect(results[:deferred]).to eq(1)
    retry_channel.close

    redis.expire(reservation_key, 0)
    final_channel = connection.create_channel
    await_dlq_depth(final_channel, 1)
    expect(final_channel.queue(target_name, durable: true).message_count).to eq(0)
    process_broker_message(final_channel)
    expect(final_channel.queue(target_name, durable: true).message_count).to eq(1)
    expect(final_channel.queue(dlq_name, durable: true).message_count).to eq(0)
    expect(redis.get(completed_key)).to eq('completed')
    final_channel.close
  end

  it 'closes the batch channel to return deferred deliveries without a head-of-queue retry loop' do
    dead_letter
    Timeout.timeout(5) { sleep 0.01 until dlq.message_count == 2 }
    allow(described_class).to receive(:acquire_channel).and_return([connection, broker_channel, false])
    allow(broker_channel.default_exchange).to receive(:publish).and_raise(IOError, 'publish failed before commit')

    described_class.send(:consume_dlq_batch)

    # Both copies share one id: each attempt is rolled back and releases the
    # reservation, so the second copy is attempted too.
    expect(broker_channel.default_exchange).to have_received(:publish).twice
    expect(broker_channel).not_to be_open
    inspection = connection.create_channel
    expect(inspection.queue(dlq_name, durable: true).message_count).to eq(2)
    expect(inspection.queue(target_name, durable: true).message_count).to eq(0)
    inspection.close
  end
end
