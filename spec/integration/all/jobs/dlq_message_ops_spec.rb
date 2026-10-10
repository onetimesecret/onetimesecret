# spec/integration/all/jobs/dlq_message_ops_spec.rb
#
# frozen_string_literal: true

# The per-message DLQ ops (#4343) against a real RabbitMQ broker:
# Onetime::Operations::Dlq::{Show, Replay(message_id:), Discard}.
#
# The unit specs (spec/unit/onetime/operations/dlq/) run on a fake broker
# that models RabbitMQ's requeue rule. These examples check the rule itself:
# a message behind the head is reached without the scan popping the head
# again (#4650), and after the op every other message is back in the DLQ in
# its original order.
#
# Queue names carry a random suffix: the test broker on 127.0.0.1:2156 is
# shared by every worktree. Counts are polled (#depth): a commit or a channel
# close returns before the queue process has applied it.
#
# Run through the lane runner:
#   tests/lanes/run simple --only spec/integration/all/jobs/dlq_message_ops_spec.rb

require 'spec_helper'
require 'bunny'
require 'uri'
require 'securerandom'
require 'onetime/operations/dlq/show'
require 'onetime/operations/dlq/replay'
require 'onetime/operations/dlq/discard'

RSpec.describe 'DLQ per-message ops', :rabbitmq, type: :integration do
  let(:connection) do
    url = ENV.fetch('RABBITMQ_URL')
    uri = URI.parse(url)
    unless uri.host == '127.0.0.1' && uri.port == 2156
      raise "Refusing to run against #{uri.host}:#{uri.port}; expected the lane test broker on 127.0.0.1:2156"
    end

    Bunny.new(url, automatically_recover: false, connection_timeout: 5, read_timeout: 5).tap(&:start)
  end
  let(:observer) { connection.create_channel }
  let(:suffix) { SecureRandom.hex(12) }
  let(:dlq_name) { "test.dlq-message-ops.dlq.#{suffix}" }
  let(:origin_name) { "test.dlq-message-ops.origin.#{suffix}" }
  let(:dlq) { observer.queue(dlq_name, durable: true) }
  let(:origin) { observer.queue(origin_name, durable: true) }
  let(:ids) { %w[A B C D E].map { |letter| "#{letter}-#{suffix}" } }
  let(:actor) { 'ur_colonel_public' }

  # A queue's ready count, polled until it reaches the expected value.
  def depth(target_queue, expected)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    count    = target_queue.message_count
    while count != expected && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.01
      count = target_queue.message_count
    end
    count
  end

  def await_dlq(expected)
    count = depth(dlq, expected)
    raise "DLQ holds #{count} messages, expected #{expected}" unless count == expected
  end

  # The message ids left in the DLQ, head first. Read with manual-ack pops on
  # the observer channel; the queue is deleted after each example.
  def remaining_ids(expected)
    await_dlq(expected)
    Array.new(expected) do
      delivery, properties, = dlq.pop(manual_ack: true)
      raise 'DLQ ran dry while reading it back' unless delivery

      properties.message_id
    end
  end

  def letters(message_ids) = message_ids.map { |id| id[0] }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)

    origin
    observer.confirm_select
    ids.each do |id|
      dlq.publish(JSON.generate(id: id), persistent: true, message_id: id, content_type: 'application/json',
        headers: { 'x-death' => [{ 'queue' => origin_name, 'reason' => 'rejected', 'count' => 1 }] })
    end
    raise 'test publishes were not confirmed' unless observer.wait_for_confirms

    await_dlq(ids.size)
  end

  after do
    if connection.open?
      cleanup = connection.create_channel
      cleanup.queue_delete(dlq_name)
      cleanup.queue_delete(origin_name)
      connection.close
    end
  end

  it 'shows a message behind the head and leaves the queue in order' do
    result = Onetime::Operations::Dlq::Show.new(connection: connection, queue: dlq_name, message_id: ids[3]).call

    expect(result).to have_attributes(found: true, scanned: 4, truncated: false)
    expect(result.message[:payload]).to eq('id' => ids[3])
    expect(letters(remaining_ids(5))).to eq(%w[A B C D E])
  end

  it 'replays a message behind the head to its origin queue, the rest staying in order' do
    result = Onetime::Operations::Dlq::Replay.new(
      connection: connection, queue: dlq_name, actor: actor, message_id: ids[3],
    ).call

    # Found at position 4: the scan did not keep re-reading the head.
    expect(result).to have_attributes(status: :success, replayed: 1, failed: 0, found: true, scanned: 4)
    expect(depth(origin, 1)).to eq(1)
    _, properties, body = origin.pop(manual_ack: true)
    expect(properties.message_id).to eq(ids[3])
    expect(JSON.parse(body)).to eq('id' => ids[3])
    expect(properties.headers).not_to have_key('x-death')
    expect(letters(remaining_ids(4))).to eq(%w[A B C E])
  end

  it 'keeps a message with no original queue instead of dropping it' do
    orphan = "F-#{suffix}"
    dlq.publish(JSON.generate(id: orphan), persistent: true, message_id: orphan, content_type: 'application/json')
    raise 'test publish was not confirmed' unless observer.wait_for_confirms

    await_dlq(6)

    result = Onetime::Operations::Dlq::Replay.new(
      connection: connection, queue: dlq_name, actor: actor, message_id: orphan,
    ).call

    expect(result).to have_attributes(status: :refused, outcome: 'no_original_queue', replayed: 0, failed: 0)
    expect(letters(remaining_ids(6))).to eq(%w[A B C D E F])
  end

  it 'discards a message behind the head, the rest staying in order' do
    result = Onetime::Operations::Dlq::Discard.new(
      connection: connection, queue: dlq_name, actor: actor, message_id: ids[2],
    ).call

    expect(result).to have_attributes(status: :success, found: true, scanned: 3, original_queue: origin_name)
    expect(letters(remaining_ids(4))).to eq(%w[A B D E])
    expect(depth(origin, 0)).to eq(0)
  end

  it 'reports a message past the scan bound as not_visible and truncated, moving nothing' do
    stub_const('Onetime::Operations::Dlq::Store::MAX_SCAN', 2)

    result = Onetime::Operations::Dlq::Discard.new(
      connection: connection, queue: dlq_name, actor: actor, message_id: ids[4],
    ).call

    expect(result).to have_attributes(status: :not_visible, found: false, scanned: 2, truncated: true)
    expect(letters(remaining_ids(5))).to eq(%w[A B C D E])
  end

  it 'reports a queue that is not declared as not_visible' do
    result = Onetime::Operations::Dlq::Replay.new(
      connection: connection, queue: "test.dlq-message-ops.undeclared.#{suffix}", actor: actor, message_id: ids[0],
    ).call

    expect(result).to have_attributes(status: :not_visible, outcome: 'not_visible', scanned: 0)
    expect(depth(dlq, 5)).to eq(5)
  end

  describe 'on the email DLQ (consumer reservation)' do
    let(:consumer) { Onetime::Jobs::Scheduled::DlqEmailConsumerJob }
    let(:redis) { Familia.dbclient }

    before { stub_const("#{consumer.name}::DLQ_NAME", dlq_name) }

    after do
      ids.each do |id|
        redis.del(consumer.replayed_marker_key(id), consumer.reservation_key(id),
          Onetime::Jobs::QueueConfig.processing_claim_key(id))
      end
    end

    it 'refuses an id the consumer already republished and leaves the queue in order' do
      redis.set(consumer.replayed_marker_key(ids[1]), 'completed', ex: 60)

      result = Onetime::Operations::Dlq::Replay.new(
        connection: connection, queue: dlq_name, actor: actor, message_id: ids[1],
      ).call

      expect(result).to have_attributes(status: :refused, outcome: 'already_replayed', replayed: 0)
      expect(depth(origin, 0)).to eq(0)
      expect(letters(remaining_ids(5))).to eq(%w[A B C D E])
    end

    it 'replays a clear id and leaves no reservation behind' do
      result = Onetime::Operations::Dlq::Replay.new(
        connection: connection, queue: dlq_name, actor: actor, message_id: ids[1],
      ).call

      expect(result).to have_attributes(status: :success, replayed: 1)
      expect(depth(origin, 1)).to eq(1)
      expect(redis.get(consumer.reservation_key(ids[1]))).to be_nil
      expect(letters(remaining_ids(4))).to eq(%w[A C D E])
    end
  end
end
