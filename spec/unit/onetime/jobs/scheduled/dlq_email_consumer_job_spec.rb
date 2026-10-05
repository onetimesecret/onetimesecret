# spec/unit/onetime/jobs/scheduled/dlq_email_consumer_job_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob with channel doubles, in two groups:
#
# - AMQP transaction: the order of tx_select, publish, ack/nack, and
#   tx_commit, and where a failure stops the batch. The same paths against a
#   real broker are in
#   spec/integration/all/jobs/dlq_email_consumer_transaction_spec.rb.
# - Replay reservation: the datastore scripts (real Valkey) that reserve a
#   message id, mark it completed after the commit, and keep a failed replay
#   retryable.

require 'spec_helper'
require 'securerandom'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob do
  describe 'AMQP transaction' do
    let(:logger) { double('logger', info: nil, debug: nil, warn: nil, error: nil) }
    let(:payload) { JSON.generate('raw' => true, 'email' => { 'to' => 'test@example.com' }) }
    let(:properties) do
      double('properties', message_id: 'dlq-message-1', content_type: 'application/json',
        headers: { 'x-death' => [{ 'queue' => 'email.message.send' }], 'x-schema-version' => 1 })
    end
    let(:delivery) { double('delivery', delivery_tag: 1) }
    let(:exchange) { double('exchange', publish: nil) }
    let(:channel) do
      double('channel', default_exchange: exchange, ack: nil, nack: nil,
        tx_select: nil, tx_commit: nil, tx_rollback: nil, open?: true, close: nil)
    end
    let(:queue) { double('queue', message_count: 2) }

    before do
      allow(described_class).to receive(:scheduler_logger).and_return(logger)
      # The replay reservation (Valkey) is stubbed here; it is covered with
      # the real scripts in the 'replay reservation' group below.
      allow(described_class).to receive(:reserve_replay).and_return(1)
      allow(described_class).to receive(:start_replay).and_return(true)
      allow(described_class).to receive(:finalize_replay)
      allow(described_class).to receive(:release_reservation)
      allow(described_class).to receive(:acquire_channel).and_return([nil, channel, false])
      allow(channel).to receive(:queue).with(described_class::DLQ_NAME, durable: true, passive: true).and_return(queue)
      allow(queue).to receive(:pop).with(manual_ack: true).and_return(
        [delivery, properties, payload], [double('delivery2', delivery_tag: 2), properties, payload])
    end

    def run_batch
      described_class.send(:consume_dlq_batch)
    end

    it 'selects transactions before popping and commits publish and ack in order' do
      allow(queue).to receive(:message_count).and_return(1)
      expect(channel).to receive(:tx_select).ordered
      expect(queue).to receive(:pop).with(manual_ack: true).ordered.and_return([delivery, properties, payload])
      expect(exchange).to receive(:publish).with(payload, routing_key: 'email.message.send',
        persistent: true, message_id: 'dlq-message-1', content_type: 'application/json',
        headers: { 'x-schema-version' => 1 }).ordered
      expect(channel).to receive(:ack).with(1).ordered
      expect(channel).to receive(:tx_commit).ordered
      expect(described_class).to receive(:finalize_replay).with('dlq-message-1', anything, anything).ordered
      expect(logger).to receive(:info).with(/replayed=1/)
      run_batch
    end

    [:publish, :ack].each do |failure|
      it "rolls back a failed #{failure}, releases its reservation, and continues to the next message" do
        target = failure == :publish ? exchange : channel
        calls = 0
        allow(target).to receive(failure) do
          calls += 1
          raise IOError, 'interrupted before commit' if calls == 1
        end
        expect(channel).to receive(:tx_rollback).once.ordered
        expect(channel).to receive(:tx_commit).once.ordered
        expect(channel).not_to receive(:nack)
        expect(described_class).to receive(:release_reservation)
          .with('dlq-message-1', anything, include_publishing: true).once
        expect(described_class).to receive(:finalize_replay).once
        expect(logger).to receive(:warn).with(/rolled back before commit: IOError/, message_id: 'dlq-message-1')
        expect(logger).to receive(:info).with(/replayed=1.*deferred=1/)
        run_batch
      end
    end

    it 'stops without settling the delivery or popping another message when rollback fails' do
      allow(channel).to receive(:ack).and_raise(IOError, 'ack interrupted')
      allow(channel).to receive(:tx_rollback).and_raise(IOError, 'channel closed')
      expect(queue).to receive(:pop).once
      expect(channel).not_to receive(:tx_commit)
      expect(channel).not_to receive(:nack)
      # No commit was sent, so the copy is not live and the next run may retry.
      expect(described_class).to receive(:release_reservation)
        .with('dlq-message-1', anything, include_publishing: true)
      expect(described_class).not_to receive(:finalize_replay)
      expect(logger).to receive(:error).with(/rollback failed; batch stopped/i, message_id: 'dlq-message-1')
      expect(channel).to receive(:close)
      run_batch
    end

    it 'stops on an unconfirmed commit without rollback, nack, or another pop' do
      allow(channel).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
      # The copy may be live: the reservation is neither released nor completed.
      expect(described_class).not_to receive(:release_reservation)
      expect(described_class).not_to receive(:finalize_replay)
      expect(queue).to receive(:pop).once
      expect(channel).not_to receive(:tx_rollback)
      expect(channel).not_to receive(:nack)
      expect(logger).to receive(:error).with(
        /outcome unknown.*may already be republished.*counts before the stop: replayed=0/i,
        message_id: 'dlq-message-1',
      )
      expect(logger).not_to receive(:info).with(/Batch complete/)
      expect(channel).to receive(:close)
      run_batch
    end

    {
      'non-auth' => JSON.generate('template' => 'secret_link'),
      'missing token' => JSON.generate('template' => 'password_reset', 'data' => {}),
      'expired token' => JSON.generate('template' => 'password_reset', 'data' => { 'account_id' => 123 }),
      'invalid JSON' => '{invalid',
    }.each do |name, body|
      it "commits the #{name} discard in transaction mode" do
        allow(described_class).to receive(:token_expired?).and_return(true)
        allow(queue).to receive(:message_count).and_return(1)
        allow(queue).to receive(:pop).and_return([delivery, properties, body])
        expect(channel).to receive(:nack).with(1, false, false).ordered
        expect(channel).to receive(:tx_commit).ordered
        expect(exchange).not_to receive(:publish)
        run_batch
      end
    end

    it 'commits the missing-route discard in transaction mode' do
      allow(properties).to receive(:headers).and_return(nil)
      allow(queue).to receive(:message_count).and_return(1)
      expect(channel).to receive(:nack).with(1, false, false).ordered
      expect(channel).to receive(:tx_commit).ordered
      expect(exchange).not_to receive(:publish)
      run_batch
    end

    it 'commits the duplicate ack without republishing' do
      allow(described_class).to receive(:reserve_replay).and_return(2)
      allow(queue).to receive(:message_count).and_return(1)
      expect(channel).to receive(:ack).with(1).ordered
      expect(channel).to receive(:tx_commit).ordered
      expect(exchange).not_to receive(:publish)
      run_batch
    end

    it 'stops on a failed duplicate ack rather than nacking the same delivery' do
      allow(described_class).to receive(:reserve_replay).and_return(2)
      allow(channel).to receive(:ack).and_raise(IOError, 'ack interrupted')
      expect(queue).to receive(:pop).once
      expect(channel).not_to receive(:nack)
      expect(channel).not_to receive(:tx_commit)
      expect(logger).to receive(:error).with(/duplicate acknowledgement failed before commit/i,
        message_id: 'dlq-message-1')
      run_batch
    end

    it 'stops on an unconfirmed discard commit rather than nacking twice' do
      allow(queue).to receive(:pop).and_return([delivery, properties, '{invalid'])
      allow(channel).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
      expect(queue).to receive(:pop).once
      expect(channel).to receive(:nack).with(1, false, false).once
      expect(channel).not_to receive(:tx_rollback)
      expect(logger).to receive(:error).with(/outcome unknown.*discard/i, message_id: 'dlq-message-1')
      run_batch
    end

    it 'does not start a transaction for an empty DLQ' do
      allow(queue).to receive(:message_count).and_return(0)
      expect(channel).not_to receive(:tx_select)
      expect(queue).not_to receive(:pop)
      run_batch
    end
  end

  describe 'replay reservation' do
    let(:message_id) { "test-dlq-replay-#{SecureRandom.uuid}" }
    let(:redis) { Familia.dbclient }
    let(:delivery) { double(delivery_tag: 42) }
    let(:properties) do
      double(message_id: message_id, content_type: 'application/json',
        headers: { 'x-death' => [{ 'queue' => 'email.message.send' }] })
    end
    let(:payload) { JSON.generate('raw' => true, 'body' => 'test auth email') }
    let(:exchange) { double(publish: nil) }
    let(:channel) { tx_channel(exchange) }
    let(:results) { { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0, deferred: 0 } }
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

    def tx_channel(target_exchange)
      double(default_exchange: target_exchange, ack: nil, nack: nil, open?: true, tx_commit: nil, tx_rollback: nil)
    end

    def process(target = channel)
      described_class.send(:process_message, target, delivery, properties, payload, results)
    end

    it 'retains the original when publish raises on a usable channel' do
      allow(exchange).to receive(:publish).and_raise(IOError, 'publish failed')

      process

      expect(channel).to have_received(:tx_rollback).once
      expect(channel).not_to have_received(:nack)
      expect(channel).not_to have_received(:ack)
      expect(results[:deferred]).to eq(1)
    end

    it 'retries on the next run after channel closure rather than treating the id as completed' do
      allow(exchange).to receive(:publish) do
        allow(channel).to receive(:open?).and_return(false)
        raise IOError, 'channel closed before publishing'
      end
      allow(channel).to receive(:tx_rollback).and_raise(IOError, 'channel is closed')
      expect { process }.to raise_error(described_class::BatchStopped, /rollback failed/i)
      expect(redis.get(reservation_key)).to be_nil
      expect(redis.get(completed_key)).to be_nil

      retry_exchange = double(publish: nil)
      retry_channel = tx_channel(retry_exchange)
      process(retry_channel)

      expect(retry_exchange).to have_received(:publish).once
      expect(retry_channel).to have_received(:ack).with(42)
      expect(redis.get(completed_key)).to eq('completed')
    end

    it 'replays a rolled-back publish on the next run' do
      allow(exchange).to receive(:publish).and_raise(IOError, 'publish failed before commit')
      process
      expect(channel).to have_received(:tx_rollback).once
      expect(channel).not_to have_received(:tx_commit)
      expect(redis.get(reservation_key)).to be_nil
      expect(redis.get(completed_key)).to be_nil
      expect(results).to include(replayed: 0, deferred: 1)

      allow(exchange).to receive(:publish).and_return(nil)
      process
      expect(channel).to have_received(:ack).with(42).once
      expect(channel).to have_received(:tx_commit).once
      expect(redis.get(completed_key)).to eq('completed')
      expect(redis.get(reservation_key)).to be_nil
      expect(results).to include(replayed: 1, deferred: 1)
    end

    it 'holds an unconfirmed commit for the uncertainty window, then replays it' do
      allow(channel).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
      expect { process }.to raise_error(described_class::BatchStopped, /outcome unknown/i)
      expect(channel).not_to have_received(:tx_rollback)
      expect(redis.get(reservation_key)).to start_with('publishing:')
      expect(redis.ttl(reservation_key)).to be_between(1, Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL)
      expect(redis.get(completed_key)).to be_nil
      expect(results[:replayed]).to eq(0)

      # The commit was not applied, so the delivery is back in the DLQ. The
      # next run neither acks it as a duplicate nor publishes it again yet.
      allow(channel).to receive(:tx_commit).and_return(nil)
      process
      expect(exchange).to have_received(:publish).once
      expect(channel).to have_received(:ack).once
      expect(channel).not_to have_received(:nack)
      expect(results[:deferred]).to eq(1)

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
      # The commit applied but its reply was lost; a worker claims the copy.
      allow(channel).to receive(:tx_commit) do
        redis.set(worker_key, '1', ex: 3600)
        raise IOError, 'broker may have applied the commit'
      end
      expect { process }.to raise_error(described_class::BatchStopped)
      allow(channel).to receive(:tx_commit).and_return(nil)

      # Another dead-lettered copy of the same id waits out the window.
      process
      expect(redis.get(worker_key)).to eq('1')
      expect(exchange).to have_received(:publish).once
      expect(channel).to have_received(:ack).once

      # After the window, the replay runs again and can send a second email.
      redis.expire(reservation_key, 0)
      process
      expect(exchange).to have_received(:publish).twice
      expect(redis.get(worker_key)).to be_nil
      expect(channel).to have_received(:ack).twice
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
      second_channel = tx_channel(second_exchange)
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

    it 'rolls back and releases the reservation when acknowledgement raises' do
      allow(channel).to receive(:ack).and_raise(IOError, 'ack failed before commit')
      process
      expect(exchange).to have_received(:publish).once
      expect(channel).to have_received(:tx_rollback).once
      expect(channel).not_to have_received(:tx_commit)
      expect(redis.get(completed_key)).to be_nil
      expect(redis.get(reservation_key)).to be_nil
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

    it 'leaves unexpected processing errors unacked instead of discarding the delivery' do
      allow(described_class).to receive(:replay_message).and_raise(RuntimeError, 'unexpected failure')
      process
      expect(channel).not_to have_received(:ack)
      expect(channel).not_to have_received(:nack)
      expect(results[:errors]).to eq(1)
      expect(results[:deferred]).to eq(1)
    end
  end
end
