# spec/lib/onetime/initializers/setup_rabbitmq_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Initializers::SetupRabbitMQ do
  # These tests use mocks to avoid requiring RabbitMQ to be running

  describe '.disconnect' do
    context 'when RabbitMQ connection exists and is open' do
      before do
        @mock_conn = instance_double(Bunny::Session, open?: true)
        allow(@mock_conn).to receive(:close)
        $rmq_conn = @mock_conn
        $rmq_channel_pool = double('ConnectionPool')
      end

      after do
        $rmq_conn = nil
        $rmq_channel_pool = nil
      end

      it 'closes the connection' do
        expect(@mock_conn).to receive(:close)
        described_class.disconnect
      end

      it 'sets $rmq_conn to nil' do
        described_class.disconnect
        expect($rmq_conn).to be_nil
      end

      it 'sets $rmq_channel_pool to nil' do
        described_class.disconnect
        expect($rmq_channel_pool).to be_nil
      end
    end

    context 'when RabbitMQ connection is already closed' do
      before do
        @mock_conn = instance_double(Bunny::Session, open?: false)
        $rmq_conn = @mock_conn
        $rmq_channel_pool = double('ConnectionPool')
      end

      after do
        $rmq_conn = nil
        $rmq_channel_pool = nil
      end

      it 'does not call close on the connection' do
        expect(@mock_conn).not_to receive(:close)
        described_class.disconnect
      end

      it 'leaves globals unchanged' do
        described_class.disconnect
        expect($rmq_conn).to eq(@mock_conn)
        expect($rmq_channel_pool).not_to be_nil
      end
    end

    context 'when $rmq_conn is nil' do
      before do
        $rmq_conn = nil
        $rmq_channel_pool = nil
      end

      it 'returns without error' do
        expect { described_class.disconnect }.not_to raise_error
      end
    end

    context 'when $rmq_conn is not defined (set to nil)' do
      before do
        $rmq_conn = nil
        $rmq_channel_pool = nil
      end

      it 'returns without error' do
        expect { described_class.disconnect }.not_to raise_error
      end
    end

    context 'when close raises an error' do
      before do
        @mock_conn = instance_double(Bunny::Session, open?: true)
        allow(@mock_conn).to receive(:close).and_raise(StandardError.new('Connection error'))
        $rmq_conn = @mock_conn
        $rmq_channel_pool = double('ConnectionPool')
      end

      after do
        $rmq_conn = nil
        $rmq_channel_pool = nil
      end

      it 'logs warning but does not raise' do
        expect { described_class.disconnect }.not_to raise_error
      end

      it 'still clears globals even on error' do
        described_class.disconnect
        expect($rmq_conn).to be_nil
        expect($rmq_channel_pool).to be_nil
      end
    end
  end

  describe '.reconnect' do
    context 'when jobs are disabled' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => false } })
      end

      it 'does not attempt to connect' do
        expect(Bunny).not_to receive(:new)
        described_class.reconnect
      end
    end

    context 'when jobs are enabled' do
      let(:mock_instance) { instance_double(described_class) }

      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(described_class).to receive(:new).and_return(mock_instance)
        allow(mock_instance).to receive(:send).with(:setup_rabbitmq_connection)
      end

      it 'creates new instance and calls setup_rabbitmq_connection' do
        expect(described_class).to receive(:new).and_return(mock_instance)
        expect(mock_instance).to receive(:send).with(:setup_rabbitmq_connection)
        described_class.reconnect
      end
    end

    context 'when connection fails' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        mock_instance = instance_double(described_class)
        allow(described_class).to receive(:new).and_return(mock_instance)
        allow(mock_instance).to receive(:send)
          .with(:setup_rabbitmq_connection)
          .and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))
      end

      it 'logs warning but does not raise' do
        expect { described_class.reconnect }.not_to raise_error
      end
    end

    context 'when timeout occurs' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        mock_instance = instance_double(described_class)
        allow(described_class).to receive(:new).and_return(mock_instance)
        allow(mock_instance).to receive(:send)
          .with(:setup_rabbitmq_connection)
          .and_raise(Bunny::ConnectionTimeout.new('Timeout'))
      end

      it 'logs warning but does not raise' do
        expect { described_class.reconnect }.not_to raise_error
      end
    end
  end
end
