# spec/lib/onetime/initializers/setup_rabbitmq_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/SpecFilePathFormat
# File name matches implementation file setup_rabbitmq.rb
RSpec.describe Onetime::Initializers::SetupRabbitMQ do
  # These tests use mocks to avoid requiring RabbitMQ to be running

  let(:instance) { described_class.new }

  describe '#cleanup' do
    context 'when RabbitMQ connection exists and is open' do
      let(:mock_conn) { instance_double(Bunny::Session, open?: true, close: true) }
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_conn         = mock_conn
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'closes the connection' do
        allow(mock_conn).to receive(:close)
        instance.cleanup
        expect(mock_conn).to have_received(:close)
      end

      it 'sets $rmq_conn to nil' do
        instance.cleanup
        expect($rmq_conn).to be_nil
      end

      it 'sets $rmq_channel_pool to nil' do
        instance.cleanup
        expect($rmq_channel_pool).to be_nil
      end
    end

    context 'when RabbitMQ connection is already closed' do
      let(:mock_conn) { instance_double(Bunny::Session, open?: false) }
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_conn         = mock_conn
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'does not call close on the connection' do
        allow(mock_conn).to receive(:close)
        instance.cleanup
        expect(mock_conn).not_to have_received(:close)
      end

      it 'clears $rmq_conn' do
        instance.cleanup
        expect($rmq_conn).to be_nil
      end

      it 'clears $rmq_channel_pool' do
        instance.cleanup
        expect($rmq_channel_pool).to be_nil
      end
    end

    context 'when $rmq_conn is nil' do
      before do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'returns without error' do
        expect { instance.cleanup }.not_to raise_error
      end
    end

    context 'when close raises an error' do
      let(:mock_conn) do
        instance_double(Bunny::Session, open?: true).tap do |conn|
          allow(conn).to receive(:close).and_raise(StandardError.new('Connection error'))
        end
      end
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_conn         = mock_conn
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'logs warning but does not raise' do
        expect { instance.cleanup }.not_to raise_error
      end

      it 'clears $rmq_conn even on error' do
        instance.cleanup
        expect($rmq_conn).to be_nil
      end

      it 'clears $rmq_channel_pool even on error' do
        instance.cleanup
        expect($rmq_channel_pool).to be_nil
      end
    end
  end

  describe '#reconnect' do
    context 'when jobs are disabled' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => false } })
      end

      it 'does not attempt to connect' do
        allow(instance).to receive(:setup_rabbitmq_connection)
        instance.reconnect
        expect(instance).not_to have_received(:setup_rabbitmq_connection)
      end
    end

    context 'when jobs are enabled' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
      end

      it 'calls setup_rabbitmq_connection' do
        instance.reconnect
        expect(instance).to have_received(:setup_rabbitmq_connection)
      end
    end

    context 'when connection fails' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))
      end

      it 'logs warning but does not raise' do
        expect { instance.reconnect }.not_to raise_error
      end
    end

    context 'when timeout occurs' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(Bunny::ConnectionTimeout.new('Timeout'))
      end

      it 'logs warning but does not raise' do
        expect { instance.reconnect }.not_to raise_error
      end
    end
  end

end
