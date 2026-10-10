# spec/unit/onetime/jobs/scheduled/dlq_email_consumer_job_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob with channel doubles, in two groups:
#
# - AMQP transaction: the order of tx_select, publish, tx_commit, ack/nack,
#   and tx_commit, and where a failure stops the batch. The same paths against a
#   real broker are in
#   spec/integration/all/jobs/dlq_email_consumer_transaction_spec.rb.
# - Replay reservation: the datastore scripts (real Valkey) that reserve a
#   message id, mark it completed after the publish commit, and keep a failed
#   replay retryable.

require 'spec_helper'
require 'securerandom'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob do
  describe 'AMQP transaction' do
    let(:logger) { double('logger', info: nil, debug: nil, warn: nil, error: nil) }
    let(:payload) { JSON.generate('raw' => true, 'email' => { 'to' => 'test@example.com' }) }
    let(:properties) do
      # The replay below expects only x-schema-version back: every death
      # header the broker stamps must be stripped.
      double('properties', message_id: 'dlq-message-1', content_type: 'application/json',
        headers: { 'x-death' => [{ 'queue' => 'email.message.send' }],
                   'x-first-death-queue' => 'email.message.send', 'x-last-death-queue' => 'email.message.send',
                   'x-schema-version' => 1 })
    end
    # The second message is dead-lettered from another queue, so a run that
    # found the first queue missing still publishes it.
    let(:other_properties) do
      double('properties', message_id: 'dlq-message-2', content_type: 'application/json',
        headers: { 'x-death' => [{ 'queue' => 'email.message.schedule' }], 'x-schema-version' => 1 })
    end
    let(:delivery) { double('delivery', delivery_tag: 1) }
    let(:exchange) { double('exchange', publish: nil, on_return: nil) }
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
        [delivery, properties, payload], [double('delivery2', delivery_tag: 2), other_properties, payload])
    end

    def run_batch
      described_class.send(:consume_dlq_batch)
    end

    # The broker returns an unroutable mandatory message while it applies
    # the commit of the publish, before it confirms that commit.
    def return_publish_on_commit(times: 1)
      handler = nil
      allow(exchange).to receive(:on_return) { |&block| handler = block }
      published = false
      allow(exchange).to receive(:publish) { published = true }
      allow(channel).to receive(:tx_commit) do
        if published && times.positive?
          times -= 1
          handler.call
        end
        published = false
      end
    end

    it 'selects transactions before popping, commits the publish, then commits the ack' do
      allow(queue).to receive(:message_count).and_return(1)
      expect(channel).to receive(:tx_select).ordered
      expect(queue).to receive(:pop).with(manual_ack: true).ordered.and_return([delivery, properties, payload])
      expect(exchange).to receive(:publish).with(payload, routing_key: 'email.message.send',
        mandatory: true, persistent: true, message_id: 'dlq-message-1', content_type: 'application/json',
        headers: { 'x-schema-version' => 1 }).ordered
      expect(channel).to receive(:tx_commit).ordered
      expect(described_class).to receive(:finalize_replay).with('dlq-message-1', anything, anything).ordered
      expect(channel).to receive(:ack).with(1).ordered
      expect(channel).to receive(:tx_commit).ordered
      expect(logger).to receive(:info).with(/replayed=1/)
      run_batch
    end

    it 'leaves a returned replay unacked, releases its reservation, and continues to the next message' do
      return_publish_on_commit
      expect(channel).to receive(:ack).with(2).once
      expect(channel).not_to receive(:ack).with(1)
      expect(channel).not_to receive(:nack)
      expect(channel).not_to receive(:tx_rollback)
      expect(described_class).to receive(:release_reservation)
        .with('dlq-message-1', anything, include_publishing: true).once
      expect(described_class).to receive(:finalize_replay).once
      expect(logger).to receive(:error).with(
        /Replay unroutable: no queue named email\.message\.send; left in the DLQ/, message_id: 'dlq-message-1'
      )
      expect(logger).to receive(:info).with(/replayed=1.*deferred=1 held=1 unroutable=1/)
      run_batch
    end

    it 'rolls back a failed publish, releases its reservation, and continues to the next message' do
      calls = 0
      allow(exchange).to receive(:publish) do
        calls += 1
        raise IOError, 'interrupted before commit' if calls == 1
      end
      expect(channel).to receive(:tx_rollback).once.ordered
      expect(channel).to receive(:tx_commit).twice.ordered
      expect(channel).not_to receive(:nack)
      expect(described_class).to receive(:release_reservation)
        .with('dlq-message-1', anything, include_publishing: true).once
      expect(described_class).to receive(:finalize_replay).once
      expect(logger).to receive(:warn).with(/rolled back before commit: IOError/, message_id: 'dlq-message-1')
      expect(logger).to receive(:info).with(/replayed=1.*deferred=1/)
      run_batch
    end

    it 'stops on a failed ack after the publish commit, with the id already marked completed' do
      allow(channel).to receive(:ack).and_raise(IOError, 'ack interrupted')
      expect(queue).to receive(:pop).once
      expect(channel).to receive(:tx_commit).once
      expect(channel).not_to receive(:tx_rollback)
      expect(channel).not_to receive(:nack)
      # The copy is live: the reservation is finalized, not released.
      expect(described_class).not_to receive(:release_reservation)
      expect(described_class).to receive(:finalize_replay).once
      expect(logger).to receive(:error).with(
        /Replay acknowledgement failed before commit; batch stopped: IOError; counts before the stop: replayed=1/,
        message_id: 'dlq-message-1',
      )
      expect(channel).to receive(:close)
      run_batch
    end

    it 'stops on an unconfirmed ack commit, with the id already marked completed' do
      commits = 0
      allow(channel).to receive(:tx_commit) do
        commits += 1
        raise IOError, 'commit reply lost' if commits == 2
      end
      expect(queue).to receive(:pop).once
      expect(channel).to receive(:ack).with(1).once
      expect(channel).not_to receive(:tx_rollback)
      expect(described_class).not_to receive(:release_reservation)
      expect(described_class).to receive(:finalize_replay).once
      expect(logger).to receive(:error).with(
        /outcome unknown: broker did not confirm replay acknowledgement.*replayed=1/, message_id: 'dlq-message-1'
      )
      run_batch
    end

    it 'stops without settling the delivery or popping another message when rollback fails' do
      allow(exchange).to receive(:publish).and_raise(IOError, 'publish interrupted')
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
      expect(channel).not_to receive(:ack)
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

    {
      'no headers' => nil,
      'no x-death header' => { 'x-schema-version' => 1 },
      'an empty x-death array' => { 'x-death' => [] },
      'an x-death entry that is not a table' => { 'x-death' => ['invalid'] },
      'an x-death header that is not an array' => { 'x-death' => 'invalid' },
      'an x-death table in place of the array' => { 'x-death' => { 'queue' => 'email.message.send' } },
      'an x-death entry without a queue' => { 'x-death' => [{ 'reason' => 'rejected' }] },
      'an empty queue name' => { 'x-death' => [{ 'queue' => '' }] },
      'a queue name that is not a string' => { 'x-death' => [{ 'queue' => 7 }] },
    }.each do |name, headers|
      it "commits the missing-route discard for #{name}" do
        allow(properties).to receive(:headers).and_return(headers)
        allow(queue).to receive(:message_count).and_return(1)
        expect(channel).to receive(:nack).with(1, false, false).ordered
        expect(channel).to receive(:tx_commit).ordered
        expect(exchange).not_to receive(:publish)
        expect(described_class).not_to receive(:reserve_replay)
        expect(logger).to receive(:error).with(/No original queue in x-death headers; discarded/,
          message_id: 'dlq-message-1')
        expect(logger).to receive(:info).with(/errors=1 deferred=0 held=0/)
        run_batch
      end
    end

    describe 'held messages' do
      let(:deliveries) { (1..4).map { |tag| [double("delivery#{tag}", delivery_tag: tag), properties, payload] } }

      before do
        stub_const("#{described_class.name}::BATCH_SIZE", 1)
        allow(queue).to receive(:message_count).and_return(deliveries.size)
        allow(queue).to receive(:pop).with(manual_ack: true).and_return(*deliveries)
      end

      it 'passes over reserved ids without counting them against the batch' do
        allow(described_class).to receive(:reserve_replay).and_return(0, 0, 1)
        expect(queue).to receive(:pop).exactly(3).times
        expect(exchange).to receive(:publish).once
        expect(channel).to receive(:ack).with(3).once
        expect(channel).not_to receive(:nack)
        expect(logger).to receive(:info).with(/replayed=1 .*deferred=2 held=2/)
        run_batch
      end

      it 'passes over unexpected processing errors without counting them against the batch' do
        calls = 0
        allow(described_class).to receive(:replay_message).and_wrap_original do |replay, *args|
          calls += 1
          raise NoMethodError, 'unexpected failure' if calls < 3

          replay.call(*args)
        end
        expect(queue).to receive(:pop).exactly(3).times
        expect(channel).to receive(:ack).with(3).once
        expect(channel).not_to receive(:nack)
        expect(logger).to receive(:info).with(/replayed=1 .*errors=2 deferred=2 held=2/)
        run_batch
      end

      it 'passes over unroutable replays without counting them against the batch, ' \
         'and holds later messages for a queue the run found missing without a reservation or a publish' do
        # Only the first replay is returned; the second, for the same queue,
        # is never published.
        return_publish_on_commit(times: 1)
        allow(queue).to receive(:pop).with(manual_ack: true).and_return(
          deliveries[0], deliveries[1], [double('delivery3', delivery_tag: 3), other_properties, payload]
        )
        expect(queue).to receive(:pop).exactly(3).times
        expect(channel).to receive(:ack).with(3).once
        expect(channel).not_to receive(:nack)
        expect(logger).to receive(:error).with(/Replay unroutable: no queue named email\.message\.send/,
          message_id: 'dlq-message-1').once
        expect(logger).to receive(:debug).with(/Replay unroutable: no queue named email\.message\.send/,
          message_id: 'dlq-message-1').once
        expect(logger).to receive(:info).with(/replayed=1 .*deferred=2 held=2 unroutable=2/)
        run_batch
        expect(exchange).to have_received(:publish).with(payload, hash_including(routing_key: 'email.message.send')).once
        expect(exchange).to have_received(:publish).with(payload, hash_including(routing_key: 'email.message.schedule')).once
        expect(described_class).to have_received(:reserve_replay).with('dlq-message-1', anything).once
        expect(described_class).to have_received(:reserve_replay).with('dlq-message-2', anything).once
      end

      it 'reaches a replayable message behind more unroutable messages than the old held limit' do
        return_publish_on_commit(times: 1)
        blocked = Array.new(600) { |i| [double("blocked#{i}", delivery_tag: i + 1), properties, payload] }
        live    = [double('live', delivery_tag: 601), other_properties, payload]
        allow(queue).to receive(:message_count).and_return(601)
        allow(queue).to receive(:pop).with(manual_ack: true).and_return(*blocked, live)
        expect(channel).to receive(:ack).with(601).once
        expect(logger).to receive(:info).with(/replayed=1 .*deferred=600 held=600 unroutable=600/)
        run_batch
        expect(exchange).to have_received(:publish).twice
      end

      it 'stops popping messages once the run budget is spent' do
        stub_const("#{described_class.name}::RUN_BUDGET", 0)
        allow(described_class).to receive(:monotonic_now).and_return(1000.0)
        allow(described_class).to receive(:reserve_replay).and_return(0)
        expect(queue).not_to receive(:pop)
        expect(exchange).not_to receive(:publish)
        expect(logger).to receive(:info).with(/replayed=0 .*deferred=0 held=0/)
        run_batch
      end

      it 'pops the next message while the run budget remains' do
        clock = [0, 1, 239, 240]
        allow(described_class).to receive(:monotonic_now) { clock.shift }
        allow(described_class).to receive(:reserve_replay).and_return(0)
        expect(queue).to receive(:pop).twice
        expect(logger).to receive(:info).with(/replayed=0 .*deferred=2 held=2/)
        run_batch
      end

      it 'does not pop more messages than the DLQ held when the run started' do
        allow(described_class).to receive(:reserve_replay).and_return(0)
        expect(queue).to receive(:pop).exactly(4).times
        run_batch
      end

      it 'counts a deferral after a datastore error against the batch' do
        allow(described_class).to receive(:reserve_replay).and_raise(Redis::TimeoutError, 'datastore unavailable')
        expect(queue).to receive(:pop).once
        expect(logger).to receive(:info).with(/deferred=1 held=0/)
        run_batch
      end

      it 'counts a deferral after a publish error against the batch' do
        allow(exchange).to receive(:publish).and_raise(IOError, 'publish interrupted')
        expect(queue).to receive(:pop).once
        expect(logger).to receive(:info).with(/deferred=1 held=0/)
        run_batch
      end
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

    it 'logs a network stop during setup with zero counts and closes the channel' do
      failure = Bunny::NetworkFailure.new('connection lost', IOError.new('socket closed'))
      allow(queue).to receive(:message_count).and_raise(failure)
      expect(queue).not_to receive(:pop)
      expect(channel).not_to receive(:tx_select)
      expect(channel).to receive(:close)
      expect(logger).to receive(:error).with(/Batch stopped: Bunny::NetworkFailure.*replayed=0.*deferred=0/)
      expect(logger).not_to receive(:info).with(/Batch complete/)
      expect { run_batch }.not_to raise_error
    end

    it 'finishes owned connection cleanup before handling a pending network failure' do
      connection = double('connection', open?: true)
      allow(described_class).to receive(:acquire_channel).and_return([connection, channel, true])
      allow(queue).to receive(:message_count).and_return(0)
      failure = Bunny::NetworkFailure.new('reader disconnected', IOError.new('socket closed'))
      closed = false
      allow(connection).to receive(:close) do
        Thread.current.raise(failure)
        closed = true
      end
      expect(logger).to receive(:error).with(/Batch stopped during cleanup: Bunny::NetworkFailure/)
      expect { run_batch }.not_to raise_error
      expect(closed).to be true
    end

    it 'does not turn unrelated setup errors into network stops' do
      allow(queue).to receive(:message_count).and_raise(ArgumentError, 'unexpected setup error')
      expect(channel).to receive(:close)
      expect { run_batch }.to raise_error(ArgumentError, 'unexpected setup error')
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
    let(:exchange) { double(publish: nil, on_return: nil) }
    let(:channel) { tx_channel(exchange) }
    let(:results) { described_class.send(:new_results) }
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

      retry_exchange = double(publish: nil, on_return: nil)
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
      expect(channel).to have_received(:tx_commit).twice
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

      # Applied or not, the delivery was not acked and is back in the DLQ.
      # The next run neither acks it as a duplicate nor publishes it again yet.
      allow(channel).to receive(:tx_commit).and_return(nil)
      process
      expect(exchange).to have_received(:publish).once
      expect(channel).not_to have_received(:ack)
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

      # The unacked delivery, back in the DLQ, waits out the window.
      process
      expect(redis.get(worker_key)).to eq('1')
      expect(exchange).to have_received(:publish).once
      expect(channel).not_to have_received(:ack)

      # After the window, the replay runs again and can send a second email.
      redis.expire(reservation_key, 0)
      process
      expect(exchange).to have_received(:publish).twice
      expect(redis.get(worker_key)).to be_nil
      expect(channel).to have_received(:ack).once
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
      second_exchange = double(publish: nil, on_return: nil)
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

    it 'acks on the next run, without a second publish, a delivery whose ack failed' do
      allow(channel).to receive(:ack).and_raise(IOError, 'ack failed after the publish commit')
      expect { process }.to raise_error(described_class::BatchStopped, /replay acknowledgement failed/i)
      expect(exchange).to have_received(:publish).once
      expect(channel).to have_received(:tx_commit).once
      expect(channel).not_to have_received(:tx_rollback)
      expect(channel).not_to have_received(:nack)
      expect(redis.get(completed_key)).to eq('completed')
      expect(redis.get(reservation_key)).to be_nil
      expect(results).to include(replayed: 1, deferred: 0)

      retry_channel = tx_channel(exchange)
      process(retry_channel)
      expect(exchange).to have_received(:publish).once
      expect(retry_channel).to have_received(:ack).with(42)
      expect(results[:replayed]).to eq(1)
    end

    it 'keeps a replay the broker returned as unroutable, and replays it once the queue exists' do
      handler = nil
      allow(exchange).to receive(:on_return) { |&block| handler = block }
      allow(channel).to receive(:tx_commit) { handler.call }
      redis.set(worker_key, '1', ex: 3600)

      process

      expect(exchange).to have_received(:publish).once
      expect(channel).not_to have_received(:ack)
      expect(channel).not_to have_received(:nack)
      expect(channel).not_to have_received(:tx_rollback)
      expect(redis.get(completed_key)).to be_nil
      expect(redis.get(reservation_key)).to be_nil
      expect(results).to include(replayed: 0, deferred: 1, held: 1, unroutable: 1)
      expect(logger).to have_received(:error).with(/Replay unroutable/, message_id: message_id)

      # The next run starts without the missing-queue memory of this one.
      results[:missing_queues].clear
      allow(channel).to receive(:tx_commit).and_return(nil)
      process
      expect(exchange).to have_received(:publish).twice
      expect(channel).to have_received(:ack).with(42).once
      expect(redis.get(completed_key)).to eq('completed')
      expect(results).to include(replayed: 1, deferred: 1, unroutable: 1)
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
      expect(results).to include(errors: 1, deferred: 1, held: 1)
    end
  end
end
