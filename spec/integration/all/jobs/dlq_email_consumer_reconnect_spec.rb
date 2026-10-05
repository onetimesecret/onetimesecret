# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'json'
require 'timeout'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe 'DLQ email consumer connection failure', :rabbitmq, type: :integration do
  let(:job) { Onetime::Jobs::Scheduled::DlqEmailConsumerJob }
  let(:url) do
    url = ENV.fetch('RABBITMQ_URL')
    uri = URI.parse(url)
    unless uri.host == '127.0.0.1' && uri.port == 2156
      raise "Refusing to run against #{uri.host}:#{uri.port}; expected the lane test broker on 127.0.0.1:2156"
    end

    url
  end
  let(:logger) { instance_double(SemanticLogger::Logger, debug: nil, info: nil, warn: nil, error: nil) }
  let(:suffix) { SecureRandom.hex(6) }
  let(:dlq_name) { "test.dlq.email.reconnect.#{suffix}" }
  let(:target_name) { "test.email.reconnect.#{suffix}" }
  let(:message_id) { "test-dlq-reconnect-#{suffix}" }
  let(:completed_key) { "dlq:replayed:#{message_id}" }
  let(:reservation_key) { "dlq:replay:reservation:#{message_id}" }
  let(:network_errors) { Queue.new }
  let(:error_handler) { double('session error handler') }
  let(:default_error_handler) { false }
  let(:observer) { Bunny.new(url, automatically_recover: false, continuation_timeout: 5_000).start }
  let(:observer_channel) { observer.create_channel }
  let(:dlq) { observer_channel.queue(dlq_name, durable: true) }
  let(:target) { observer_channel.queue(target_name, durable: true) }

  before do
    # Observe reader-thread failure without an asynchronous exception racing
    # the assertions; synchronous transport failures must still raise.
    processing_thread = Thread.current
    allow(error_handler).to receive(:raise) do |error|
      network_errors << error
      raise error if Thread.current == processing_thread
    end
    allow(Bunny).to receive(:new).and_wrap_original do |original, *args, **options|
      options[:session_error_handler] = error_handler unless default_error_handler
      original.call(*args, **options, network_recovery_interval: 0.01)
    end
    @shared_connection = Bunny.new(url).start
    @previous_connection = $rmq_conn
    $rmq_conn = @shared_connection

    allow(OT).to receive(:conf).and_return({ 'jobs' => { 'rabbitmq_url' => url } })
    allow(job).to receive(:scheduler_logger).and_return(logger)
    stub_const('Onetime::Jobs::Scheduled::DlqEmailConsumerJob::DLQ_NAME', dlq_name)

    target
    observer_channel.confirm_select
    dlq.publish(
      JSON.generate(template: 'password_reset', data: { account_id: 'test-account' }),
      headers: { 'x-death' => [{ 'queue' => target_name }] },
      content_type: 'application/json',
      message_id: message_id,
    )
    expect(observer_channel.wait_for_confirms).to be true
    expect(dlq.message_count).to eq(1)

    allow(job).to receive(:acquire_channel).and_wrap_original do |original|
      acquired = original.call
      @batch_connection, @batch_channel = acquired
      acquired
    end
  end

  after do
    $rmq_conn = @previous_connection
    Familia.dbclient.del(completed_key, reservation_key,
      Onetime::Jobs::QueueConfig.processing_claim_key(message_id))
    @batch_connection.close if @batch_connection&.open?
    @shared_connection.close if @shared_connection&.open?
    dlq.delete
    target.delete
    observer.close
  end

  context 'with Bunny’s default asynchronous error handler' do
    let(:default_error_handler) { true }


    def disconnect_batch
      # Finish closing the socket before Bunny interrupts the owning thread.
      Thread.handle_interrupt(Bunny::NetworkFailure => :never) do
        socket = @batch_connection.transport.socket
        socket.shutdown
        socket.close
      end
      Timeout.timeout(5) { Queue.new.pop }
    end

    [:after_pop, :before_commit, :after_commit].each do |phase|
      it "logs a stop for a disconnect #{phase} without losing the delivery or clearing an uncertain reservation" do
        allow(job).to receive(:token_expired?).and_return(false)
        allow(job).to receive(:acquire_channel).and_wrap_original do |original|
          acquired = original.call
          @batch_connection, @batch_channel = acquired
          if phase == :after_pop
            allow(@batch_channel).to receive(:basic_get).and_wrap_original do |pop, *args, **kwargs|
              pop.call(*args, **kwargs)
              disconnect_batch
            end
          end
          acquired
        end
        unless phase == :after_pop
          allow(job).to receive(:commit_transaction).and_wrap_original do |commit, *args|
            commit.call(*args) if phase == :after_commit
            disconnect_batch
          end
        end

        expect { job.send(:consume_dlq_batch) }.not_to raise_error

        expect(logger).to have_received(:error).with(/batch stopped.*NetworkFailure/i).at_least(:once)
        expect(logger).not_to have_received(:info).with(/Batch complete/)
        expect(@batch_channel.recoveries_counter.get).to eq(0)
        expect(@batch_connection).not_to be_open
        expect(@shared_connection).to be_open
        committed = phase == :after_commit
        Timeout.timeout(5) { sleep 0.01 until dlq.message_count == (committed ? 0 : 1) }
        expect(target.message_count).to eq(committed ? 1 : 0)
        expect(Familia.dbclient.get(completed_key)).to be_nil
        if phase == :after_pop
          expect(Familia.dbclient.get(reservation_key)).to be_nil
        else
          expect(Familia.dbclient.get(reservation_key)).to start_with('publishing:')
        end

        failed_connection = @batch_connection
        allow(job).to receive(:commit_transaction).and_call_original
        allow(job).to receive(:acquire_channel).and_wrap_original do |original|
          acquired = original.call
          @batch_connection, @batch_channel = acquired
          acquired
        end
        # An uncertain replay waits for the existing reservation to expire.
        if phase == :before_commit
          job.send(:consume_dlq_batch)
          expect(dlq.message_count).to eq(1)
          expect(target.message_count).to eq(0)
          Familia.dbclient.del(reservation_key)
        end
        job.send(:consume_dlq_batch)
        expect(@batch_connection).not_to equal(failed_connection)
        expect(dlq.message_count).to eq(0)
        expect(target.message_count).to eq(1)
        expect(Familia.dbclient.get(completed_key)).to eq('completed') unless committed
      end
    end
  end

  it 'stops the batch on a disconnect during the token lookup and retries on a fresh connection next run' do
    allow(job).to receive(:token_expired?) do
      recovery_count = @batch_channel.recoveries_counter.get
      # shutdown first: closing the descriptor alone does not wake the
      # reader thread's blocked read on Linux.
      socket = @batch_connection.transport.socket
      socket.shutdown
      socket.close

      Timeout.timeout(10) do
        if @batch_connection.automatically_recover?
          # On the old shared-connection path, let recovery finish before
          # processing resumes: Bunny then silently skips the old delivery tag.
          sleep 0.01 until @batch_channel.recoveries_counter.get > recovery_count
        else
          network_errors.pop
        end
      end
      false
    end

    # The failed publish and rollback end the batch as a logged stop
    # (BatchStopped), not as a raised error.
    job.send(:consume_dlq_batch)

    expect(logger).to have_received(:error).with(/batch stopped/i, anything)
    expect(logger).not_to have_received(:info).with(/Batch complete/)
    expect(target.message_count).to eq(0)
    Timeout.timeout(5) { sleep 0.01 until dlq.message_count == 1 }
    expect(@batch_channel.recoveries_counter.get).to eq(0)
    expect(@shared_connection).to be_open
    # Nothing was committed, so the id is neither reserved nor completed.
    expect(Familia.dbclient.exists?(reservation_key)).to be(false)
    expect(Familia.dbclient.exists?(completed_key)).to be(false)

    failed_connection = @batch_connection
    allow(job).to receive(:token_expired?).and_return(false)
    job.send(:consume_dlq_batch)

    expect(@batch_connection).not_to equal(failed_connection)
    expect(dlq.message_count).to eq(0)
    expect(target.message_count).to eq(1)
    expect(logger).to have_received(:info).with(/Batch complete: replayed=1 /)
    expect(Familia.dbclient.get(completed_key)).to eq('completed')
  end
end
