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
  let(:results) { described_class.send(:new_results) }
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
  # test target. Waits for the broker's confirm: the job reads the DLQ's
  # message count first, and that count can lag an unconfirmed publish.
  # Publishes on its own channel: a channel in confirm mode cannot switch to
  # the transaction mode the job puts broker_channel in.
  def dead_letter(id = message_id)
    publisher = connection.create_channel
    publisher.confirm_select
    publisher.default_exchange.publish(payload, routing_key: dlq_name, message_id: id,
      content_type: 'application/json', headers: { 'x-death' => [{ 'queue' => target_name }] })
    publisher.wait_for_confirms
  ensure
    publisher&.close
  end

  # A queue's ready count, polled briefly until it reaches the expected
  # value. The count can lag a publish or a requeue by a moment.
  def ready_count(ch, name, expected)
    queue    = ch.queue(name, durable: true)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    count    = queue.message_count
    while count != expected && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.01
      count = queue.message_count
    end
    count
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
    expect(ready_count(retry_channel, dlq_name, 1)).to eq(1)
    process_broker_message(retry_channel)
    expect(ready_count(retry_channel, target_name, 1)).to eq(1)
    expect(ready_count(retry_channel, dlq_name, 0)).to eq(0)
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
    expect(ready_count(retry_channel, dlq_name, 1)).to eq(1)
    process_broker_message(retry_channel)
    expect(ready_count(retry_channel, target_name, 1)).to eq(1)
    expect(ready_count(retry_channel, dlq_name, 0)).to eq(0)
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
    expect(ready_count(inspection, dlq_name, 2)).to eq(2)
    expect(ready_count(inspection, target_name, 0)).to eq(0)
    inspection.close
  end

  it 'passes over a held replay at the front of the DLQ without counting it against the batch' do
    other_id = "#{message_id}-behind"
    dead_letter(other_id)
    redis.set(reservation_key, 'publishing:another-run', ex: 3600)
    stub_const("#{described_class.name}::BATCH_SIZE", 1)
    allow(described_class).to receive(:acquire_channel).and_return([connection, broker_channel, false])

    described_class.send(:consume_dlq_batch)

    inspection = connection.create_channel
    expect(ready_count(inspection, dlq_name, 1)).to eq(1)
    expect(ready_count(inspection, target_name, 1)).to eq(1)
    _info, props, _body = inspection.queue(target_name, durable: true).pop
    expect(props.message_id).to eq(other_id)
    expect(redis.get(reservation_key)).to eq('publishing:another-run')
    inspection.close
  ensure
    redis.del("dlq:replayed:#{other_id}", "dlq:replay:reservation:#{other_id}",
      Onetime::Jobs::QueueConfig.processing_claim_key(other_id))
  end

  it 'stops a run once its time budget is spent, leaving held replays in the DLQ' do
    dead_letter
    redis.set(reservation_key, 'publishing:another-run', ex: 3600)
    # Deadline, one in-budget check, then a clock past the deadline.
    clock = [0, 0, described_class::RUN_BUDGET + 1]
    allow(described_class).to receive(:monotonic_now) { clock.shift }
    allow(described_class).to receive(:acquire_channel).and_return([connection, broker_channel, false])
    allow(described_class).to receive(:process_message).and_call_original

    described_class.send(:consume_dlq_batch)

    expect(described_class).to have_received(:process_message).once
    inspection = connection.create_channel
    expect(ready_count(inspection, dlq_name, 2)).to eq(2)
    inspection.close
  end
end
