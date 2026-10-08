# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob do
  let(:url) { 'amqp://127.0.0.1:2156' }
  let(:channel) { instance_double(Bunny::Channel, open?: true, close: nil, tx_select: nil) }
  let(:connection) { instance_double(Bunny::Session, start: nil, create_channel: channel, open?: true, close: nil) }
  let(:logger) { instance_double(SemanticLogger::Logger, debug: nil, info: nil, error: nil) }

  before do
    allow(OT).to receive(:conf).and_return({ 'jobs' => { 'rabbitmq_url' => url } })
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    allow(Bunny).to receive(:new).and_return(connection)
  end

  describe '.acquire_channel' do
    it 'owns a non-recovering connection even when the shared connection is open' do
      shared = instance_double(Bunny::Session, open?: true)
      previous_connection = $rmq_conn
      $rmq_conn = shared

      expect(shared).not_to receive(:create_channel)
      expect(described_class.send(:acquire_channel)).to eq([connection, channel, true])
      expect(Bunny).to have_received(:new).with(url, hash_including(
        automatically_recover: false,
        recover_from_connection_close: false,
        continuation_timeout: 15_000,
      ))
      expect(connection).not_to have_received(:close)
    ensure
      $rmq_conn = previous_connection
    end

    it 'applies the configured TLS options to the dedicated connection' do
      tls_options = { tls: true, verify_peer: true, tls_ca_certificates: ['/test/ca.pem'] }
      allow(Onetime::Jobs::QueueConfig).to receive(:tls_options).with(url).and_return(tls_options)

      described_class.send(:acquire_channel)

      expect(Bunny).to have_received(:new).with(url, hash_including(tls_options))
    end

    it 'closes the connection if starting it fails' do
      allow(connection).to receive(:start).and_raise(Bunny::ConnectionTimeout, 'connection timed out')

      expect(described_class.send(:acquire_channel)).to eq([nil, nil, false])
      expect(connection).to have_received(:close)
      expect(logger).to have_received(:error).with(/Connection failed/)
    end

    it 'closes the connection and propagates a channel creation failure' do
      allow(connection).to receive(:create_channel).and_raise(IOError, 'connection lost')

      expect { described_class.send(:acquire_channel) }.to raise_error(IOError, 'connection lost')
      expect(connection).to have_received(:close)
    end
  end

  describe '.consume_dlq_batch' do
    let(:queue) { instance_double(Bunny::Queue, message_count: 0) }

    before do
      allow(channel).to receive(:queue).with(described_class::DLQ_NAME, durable: true, passive: true).and_return(queue)
    end

    it 'closes its connection after an empty batch' do
      described_class.send(:consume_dlq_batch)

      expect(channel).to have_received(:close)
      expect(connection).to have_received(:close)
    end

    it 'closes its connection when the DLQ has not been declared' do
      allow(channel).to receive(:queue).and_raise(Bunny::NotFound.new('queue not found', channel, nil))

      described_class.send(:consume_dlq_batch)

      expect(connection).to have_received(:close)
    end

    it 'closes its connection when processing fails' do
      allow(queue).to receive(:message_count).and_return(1)
      allow(queue).to receive(:pop).with(manual_ack: true).and_raise(IOError, 'connection lost')

      expect { described_class.send(:consume_dlq_batch) }.to raise_error(IOError, 'connection lost')
      expect(connection).to have_received(:close)
      expect(logger).not_to have_received(:info).with(/Batch complete/)
    end

    it 'does not attempt a channel-close handshake on a disconnected connection' do
      allow(connection).to receive(:open?).and_return(false)

      described_class.send(:consume_dlq_batch)

      expect(channel).not_to have_received(:close)
      expect(connection).to have_received(:close)
    end

    it 'still closes its connection if channel cleanup fails' do
      allow(channel).to receive(:close).and_raise(IOError, 'channel close failed')

      expect { described_class.send(:consume_dlq_batch) }.to raise_error(IOError, 'channel close failed')
      expect(connection).to have_received(:close)
    end
  end
end
