# spec/integration/all/jobs/dlq_email_consumer_recovery_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob against a real RabbitMQ broker and the test Valkey:
# a replay whose publish fails leaves the original in the DLQ, unacked until
# the job's channel closes, and a later run replays it. The replay
# reservation and completed marker are the job's real datastore keys.
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
  # test target. Waits for the broker's confirm: the job reads the DLQ's
  # message count first, and that count can lag an unconfirmed publish.
  def dead_letter(id = message_id)
    broker_channel.confirm_select unless broker_channel.using_publisher_confirmations?
    broker_channel.default_exchange.publish(payload, routing_key: dlq_name, message_id: id,
      content_type: 'application/json', headers: { 'x-death' => [{ 'queue' => target_name }] })
    broker_channel.wait_for_confirms
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

  def process_broker_message(ch)
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

    redis.expire(reservation_key, 0)
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
    process_broker_message(broker_channel)
    expect(redis.get(completed_key)).to be_nil
    redis.expire(reservation_key, 0)

    retry_channel = connection.create_channel
    expect(ready_count(retry_channel, dlq_name, 1)).to eq(1)
    process_broker_message(retry_channel)
    expect(ready_count(retry_channel, target_name, 1)).to eq(1)
    expect(ready_count(retry_channel, dlq_name, 0)).to eq(0)
    retry_channel.close
  end

  it 'closes the batch channel to return deferred deliveries without a head-of-queue retry loop' do
    dead_letter
    allow(described_class).to receive(:acquire_channel).and_return([connection, broker_channel, false])
    allow(broker_channel.default_exchange).to receive(:publish).and_raise(IOError, 'transport outcome unknown')

    described_class.send(:consume_dlq_batch)

    expect(broker_channel.default_exchange).to have_received(:publish).once
    expect(broker_channel).not_to be_open
    inspection = connection.create_channel
    expect(ready_count(inspection, dlq_name, 2)).to eq(2)
    expect(ready_count(inspection, target_name, 0)).to eq(0)
    inspection.close
  end
end
