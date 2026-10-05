# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob do
  let(:message_id) { "test-dlq-replay-#{SecureRandom.uuid}" }
  let(:redis) { Familia.dbclient }
  let(:delivery) { double(delivery_tag: 42) }
  let(:properties) do
    double(message_id: message_id, content_type: 'application/json',
      headers: { 'x-death' => [{ 'queue' => 'email.message.send' }] })
  end
  let(:payload) { JSON.generate('raw' => true, 'body' => 'test auth email') }
  let(:exchange) { double(publish: nil) }
  let(:channel) { double(default_exchange: exchange, ack: nil, nack: nil, open?: true) }
  let(:results) { { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0, deferred: 0, held: 0 } }
  let(:logger) { double(info: nil, warn: nil, error: nil, debug: nil) }
  let(:completed_key) { "dlq:replayed:#{message_id}" }
  let(:reservation_key) { "dlq:replay:reservation:#{message_id}" }
  let(:worker_key) { Onetime::Jobs::QueueConfig.processing_claim_key(message_id) }

  before do
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    allow(described_class).to receive(:dbclient).and_return(redis)
  end

  after do
    redis.del(completed_key, reservation_key, worker_key)
  end

  def process(target = channel)
    described_class.send(:process_message, target, delivery, properties, payload, results)
  end

  it 'retains the original when publish raises on a usable channel' do
    allow(exchange).to receive(:publish).and_raise(IOError, 'publish failed')

    process

    expect(channel).not_to have_received(:nack)
    expect(channel).not_to have_received(:ack)
    expect(results[:deferred]).to eq(1)
  end

  it 'retries after channel closure rather than treating the premature marker as completion' do
    allow(exchange).to receive(:publish) do
      allow(channel).to receive(:open?).and_return(false)
      raise IOError, 'channel closed before publishing'
    end
    allow(channel).to receive(:nack).and_raise(IOError, 'channel is closed')
    expect { process }.not_to raise_error

    # An uncertain publish is eligible again after its reservation expires.
    redis.expire(reservation_key, 0)
    retry_exchange = double(publish: nil)
    retry_channel = double(default_exchange: retry_exchange, ack: nil, nack: nil, open?: true)
    process(retry_channel)

    expect(retry_exchange).to have_received(:publish).once
    expect(retry_channel).to have_received(:ack).with(42)
  end

  it 'retries a publish error after the uncertainty window, not in the same batch' do
    allow(exchange).to receive(:publish).and_raise(IOError, 'transport result unknown')
    process
    expect(redis.get(reservation_key)).to start_with('publishing:')
    expect(redis.ttl(reservation_key)).to be_between(1, Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL)
    expect(redis.get(completed_key)).to be_nil

    allow(exchange).to receive(:publish).and_return(nil)
    process
    expect(exchange).to have_received(:publish).once
    expect(channel).not_to have_received(:ack)

    redis.expire(reservation_key, 0)
    process
    expect(exchange).to have_received(:publish).twice
    expect(redis.get(completed_key)).to eq('completed')
    expect(redis.get(reservation_key)).to be_nil
  end

  it 'defers an overlapping run without publishing, acking, or releasing the owner' do
    owner = SecureRandom.uuid
    expect(described_class.send(:reserve_replay, message_id, owner)).to eq(1)
    expect(redis.ttl(reservation_key)).to be_between(1, described_class::RESERVATION_TTL)

    process

    expect(redis.get(reservation_key)).to eq(owner)
    expect(exchange).not_to have_received(:publish)
    expect(channel).not_to have_received(:ack)
    expect(channel).not_to have_received(:nack)
    expect(results[:deferred]).to eq(1)
  end

  it 'fences an expired owner from starting, releasing, or completing a newer reservation' do
    old_owner = SecureRandom.uuid
    new_owner = SecureRandom.uuid
    described_class.send(:reserve_replay, message_id, old_owner)
    redis.expire(reservation_key, 0)
    described_class.send(:reserve_replay, message_id, new_owner)

    expect(described_class.send(:start_replay, message_id, old_owner)).to be(false)
    described_class.send(:release_reservation, message_id, old_owner)
    expect(redis.get(reservation_key)).to eq(new_owner)
    expect(described_class.send(:start_replay, message_id, new_owner)).to be(true)
    described_class.send(:finalize_replay, message_id, old_owner, results)
    expect(redis.get(completed_key)).to be_nil
    expect(redis.get(reservation_key)).to eq("publishing:#{new_owner}")
    expect(results[:errors]).to eq(1)
  end

  it "releases the worker's leftover claim before it republishes" do
    redis.set(worker_key, '1', ex: 3600)
    published_under_claim = nil
    allow(exchange).to receive(:publish) { published_under_claim = redis.exists?(worker_key) }

    process

    expect(published_under_claim).to be(false)
    expect(channel).to have_received(:ack).with(42)
    expect(results).to include(replayed: 1, deferred: 0)
    expect(redis.get(completed_key)).to eq('completed')
  end

  it "leaves a live copy's claim alone until the uncertainty window ends" do
    allow(exchange).to receive(:publish) do
      redis.set(worker_key, '1', ex: 3600)
      raise IOError, 'broker may have accepted the copy'
    end
    process
    allow(exchange).to receive(:publish).and_return(nil)

    process
    expect(redis.get(worker_key)).to eq('1')
    expect(exchange).to have_received(:publish).once
    expect(channel).not_to have_received(:ack)

    # After the window, the replay runs again and can send a second email.
    redis.expire(reservation_key, 0)
    process
    expect(exchange).to have_received(:publish).twice
    expect(redis.get(worker_key)).to be_nil
    expect(channel).to have_received(:ack).with(42)
  end

  it 'acks a completed marker without touching the live worker claim' do
    redis.set(completed_key, 'completed', ex: 3600)
    redis.set(worker_key, '1', ex: 3600)
    process
    expect(channel).to have_received(:ack).with(42)
    expect(exchange).not_to have_received(:publish)
    expect(redis.get(worker_key)).to eq('1')
  end

  it 'never silently discards an unfinished legacy marker' do
    redis.set(completed_key, '1', ex: 3600)
    process
    expect(channel).not_to have_received(:ack)
    expect(channel).not_to have_received(:nack)
    expect(exchange).not_to have_received(:publish)
    expect(results[:deferred]).to eq(1)

    redis.expire(completed_key, 0)
    process
    expect(exchange).to have_received(:publish).once
    expect(channel).to have_received(:ack).with(42)
  end

  it 'recovers a reservation applied by Redis before its reply times out' do
    first = true
    allow(redis).to receive(:eval).and_wrap_original do |method, *args, **kwargs|
      value = method.call(*args, **kwargs)
      if first && args.first == described_class::RESERVE_REPLAY_LUA
        first = false
        raise Redis::TimeoutError, 'reply lost after SET'
      end
      value
    end
    process
    expect(exchange).not_to have_received(:publish)
    expect(channel).not_to have_received(:ack)
    expect(redis.get(completed_key)).to be_nil
    expect(redis.get(reservation_key)).to be_nil

    process
    expect(exchange).to have_received(:publish).once
    expect(channel).to have_received(:ack).with(42)
  end

  it 'retains a TTL-bounded reservation when both reservation and cleanup results are unknown' do
    allow(redis).to receive(:eval).and_wrap_original do |method, *args, **kwargs|
      raise Redis::TimeoutError, 'cleanup unavailable' if args.first == described_class::RELEASE_RESERVATION_LUA
      value = method.call(*args, **kwargs)
      raise Redis::TimeoutError, 'reservation reply lost' if args.first == described_class::RESERVE_REPLAY_LUA
      value
    end
    process
    expect(redis.get(reservation_key)).not_to be_nil
    expect(redis.ttl(reservation_key)).to be_between(1, described_class::RESERVATION_TTL)
    expect(channel).not_to have_received(:ack)
    expect(exchange).not_to have_received(:publish)
  end

  it 'recovers an ambiguous start result without publishing or waiting on an unused lease' do
    first = true
    allow(redis).to receive(:eval).and_wrap_original do |method, *args, **kwargs|
      value = method.call(*args, **kwargs)
      if first && args.first == described_class::START_REPLAY_LUA
        first = false
        raise Redis::TimeoutError, 'start reply lost'
      end
      value
    end
    process
    expect(redis.get(reservation_key)).to be_nil
    expect(redis.get(completed_key)).to be_nil
    expect(exchange).not_to have_received(:publish)
    expect(channel).not_to have_received(:ack)
    expect(results[:deferred]).to eq(1)

    process
    expect(exchange).to have_received(:publish).once
    expect(channel).to have_received(:ack).with(42)
  end

  it 'cannot clean up another owner publishing after an ambiguous datastore result' do
    old_owner = SecureRandom.uuid
    new_owner = SecureRandom.uuid
    redis.set(reservation_key, "publishing:#{new_owner}", ex: 3600)
    described_class.send(:release_reservation, message_id, old_owner, include_publishing: true)
    expect(redis.get(reservation_key)).to eq("publishing:#{new_owner}")
  end

  it 'defers a second delivery of the same id while the first replay is publishing, then acks it' do
    second_exchange = double(publish: nil)
    second_channel = double(default_exchange: second_exchange, ack: nil, nack: nil, open?: true)
    allow(exchange).to receive(:publish) do
      # The replayed copy is claimed by a worker, and an overlapping run pops
      # another dead-lettered copy of the same id before this run finishes.
      redis.set(worker_key, '1', ex: 3600)
      process(second_channel)
    end

    process

    expect(second_exchange).not_to have_received(:publish)
    expect(second_channel).not_to have_received(:ack)
    expect(second_channel).not_to have_received(:nack)
    expect(redis.get(worker_key)).to eq('1')
    expect(channel).to have_received(:ack).with(42)
    expect(results).to include(replayed: 1, deferred: 1, errors: 0)
    expect(redis.get(completed_key)).to eq('completed')

    process(second_channel)
    expect(second_channel).to have_received(:ack).with(42)
    expect(second_exchange).not_to have_received(:publish)
    expect(redis.get(worker_key)).to eq('1')
  end

  it 'retains the publishing reservation when acknowledgement raises' do
    allow(channel).to receive(:ack).and_raise(IOError, 'ack result unknown')
    process
    expect(exchange).to have_received(:publish).once
    expect(redis.get(completed_key)).to be_nil
    expect(redis.get(reservation_key)).to start_with('publishing:')
    expect(channel).not_to have_received(:nack)
    expect(results[:deferred]).to eq(1)
  end

  it 'reports finalization failure after settlement without releasing the live worker claim' do
    allow(exchange).to receive(:publish) { redis.set(worker_key, '1', ex: 3600) }
    allow(redis).to receive(:eval).and_wrap_original do |method, *args, **kwargs|
      raise Redis::TimeoutError, 'finalization unavailable' if args.first == described_class::COMPLETE_REPLAY_LUA
      method.call(*args, **kwargs)
    end
    process
    expect(channel).to have_received(:ack).with(42)
    expect(channel).not_to have_received(:nack)
    expect(redis.get(completed_key)).to be_nil
    expect(redis.get(reservation_key)).to start_with('publishing:')
    expect(redis.get(worker_key)).to eq('1')
    expect(results[:replayed]).to eq(1)
    expect(results[:errors]).to eq(1)
    expect(logger).to have_received(:error).with(/marker finalization unknown/, message_id: message_id)

    process
    expect(exchange).to have_received(:publish).once
    expect(channel).to have_received(:ack).once
  end

  it 'recognizes completion applied before the finalization reply times out' do
    allow(redis).to receive(:eval).and_wrap_original do |method, *args, **kwargs|
      value = method.call(*args, **kwargs)
      raise Redis::TimeoutError, 'completion reply lost' if args.first == described_class::COMPLETE_REPLAY_LUA
      value
    end
    process
    expect(redis.get(completed_key)).to eq('completed')
    expect(results[:errors]).to eq(1)
    process
    expect(exchange).to have_received(:publish).once
    expect(channel).to have_received(:ack).twice
  end

  it 'discards a template message whose data is false instead of deferring it' do
    template_payload = JSON.generate('template' => 'password_reset', 'data' => false)
    described_class.send(:process_message, channel, delivery, properties, template_payload, results)
    expect(channel).to have_received(:nack).with(42, false, false)
    expect(exchange).not_to have_received(:publish)
    expect(results).to include(errors: 1, deferred: 0)
  end

  it 'leaves unexpected processing errors unacked instead of discarding the delivery' do
    allow(described_class).to receive(:replay_message).and_raise(RuntimeError, 'unexpected failure')
    process
    expect(channel).not_to have_received(:ack)
    expect(channel).not_to have_received(:nack)
    expect(results[:errors]).to eq(1)
    expect(results[:deferred]).to eq(1)
  end
end
