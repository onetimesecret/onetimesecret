# spec/onetime/jobs/publisher_spec.rb
#
# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/onetime/jobs/publisher'

RSpec.describe Onetime::Jobs::Publisher do
  describe 'class methods' do
    it 'responds to enqueue_email' do
      expect(described_class).to respond_to(:enqueue_email)
    end

    it 'responds to enqueue_email_raw' do
      expect(described_class).to respond_to(:enqueue_email_raw)
    end

    it 'responds to schedule_email' do
      expect(described_class).to respond_to(:schedule_email)
    end
  end

  describe 'instance methods' do
    subject(:publisher) { described_class.new }

    it 'responds to enqueue_email' do
      expect(publisher).to respond_to(:enqueue_email)
    end

    it 'responds to schedule_email' do
      expect(publisher).to respond_to(:schedule_email)
    end

    it 'responds to publish' do
      expect(publisher).to respond_to(:publish)
    end
  end

  describe 'constants' do
    it 'defines FALLBACK_STRATEGIES with valid options' do
      expect(described_class::FALLBACK_STRATEGIES).to eq(%i[async_thread sync raise none])
    end

    it 'defines DEFAULT_FALLBACK as :async_thread' do
      expect(described_class::DEFAULT_FALLBACK).to eq(:async_thread)
    end
  end

  describe '#publish with RabbitMQ' do
    subject(:publisher) { described_class.new }

    it 'includes message_id in UUID format when publishing' do
      mock_channel = double('channel')
      mock_exchange = double('default_exchange')
      mock_channel_pool = double('channel_pool')

      allow(mock_channel_pool).to receive(:with).and_yield(mock_channel)
      allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)

      $rmq_channel_pool = mock_channel_pool

      publisher.publish('test.queue', { data: 'test' })

      expect(mock_exchange).to have_received(:publish) do |payload, options|
        expect(options[:message_id]).to match(/^[0-9a-f-]{36}$/)
      end
    end
  end

  describe '#enqueue_email without RabbitMQ' do
    subject(:publisher) { described_class.new }

    before do
      $rmq_channel_pool = nil
    end

    context 'with fallback: :sync' do
      it 'falls back to synchronous email delivery' do
        allow(Onetime::Mail).to receive(:deliver)

        publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :sync)

        expect(Onetime::Mail).to have_received(:deliver).with(:welcome, { email: 'test@example.com' })
      end
    end

    context 'with fallback: :async_thread (default)' do
      it 'spawns a thread for email delivery' do
        allow(Onetime::Mail).to receive(:deliver)

        # Default fallback spawns a thread
        publisher.enqueue_email(:welcome, { email: 'test@example.com' })

        # Give the thread time to execute
        sleep 0.1

        expect(Onetime::Mail).to have_received(:deliver).with(:welcome, { email: 'test@example.com' })
      end
    end

    context 'with fallback: :none' do
      it 'does not attempt to send email' do
        allow(Onetime::Mail).to receive(:deliver)

        publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :none)

        expect(Onetime::Mail).not_to have_received(:deliver)
      end
    end

    context 'with fallback: :raise' do
      it 'raises DeliveryError' do
        expect {
          publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :raise)
        }.to raise_error(Onetime::Mail::DeliveryError, /RabbitMQ unavailable/)
      end
    end

    context 'with invalid fallback strategy' do
      it 'raises ArgumentError' do
        expect {
          publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :invalid)
        }.to raise_error(ArgumentError, /Invalid fallback strategy/)
      end
    end
  end

  describe '#enqueue_email_raw without RabbitMQ' do
    subject(:publisher) { described_class.new }

    before do
      $rmq_channel_pool = nil
    end

    let(:raw_email) { { to: 'test@example.com', from: 'noreply@example.com', subject: 'Test', body: 'Hello' } }

    context 'with fallback: :sync' do
      it 'falls back to synchronous raw email delivery' do
        allow(Onetime::Mail).to receive(:deliver_raw)

        publisher.enqueue_email_raw(raw_email, fallback: :sync)

        expect(Onetime::Mail).to have_received(:deliver_raw).with(raw_email)
      end
    end
  end

  describe '.enqueue_transient' do
    it 'responds to enqueue_transient class method' do
      expect(described_class).to respond_to(:enqueue_transient)
    end
  end

  describe '#enqueue_transient' do
    subject(:publisher) { described_class.new }

    it 'responds to enqueue_transient instance method' do
      expect(publisher).to respond_to(:enqueue_transient)
    end

    context 'without RabbitMQ (jobs disabled)' do
      before do
        $rmq_channel_pool = nil
      end

      it 'returns false when jobs are disabled' do
        result = publisher.enqueue_transient('domain.verified', { domain: 'example.com' })

        expect(result).to be false
      end

      it 'does not raise errors when jobs are disabled' do
        expect {
          publisher.enqueue_transient('domain.verified', { domain: 'example.com' })
        }.not_to raise_error
      end
    end

    context 'input validation' do
      before do
        $rmq_channel_pool = nil
      end

      it 'returns false for nil event_type' do
        result = publisher.enqueue_transient(nil, { domain: 'example.com' })

        expect(result).to be false
      end

      it 'returns false for empty event_type' do
        result = publisher.enqueue_transient('', { domain: 'example.com' })

        expect(result).to be false
      end

      it 'returns false for whitespace-only event_type' do
        result = publisher.enqueue_transient('   ', { domain: 'example.com' })

        expect(result).to be false
      end

      it 'accepts symbol event_type and coerces to string' do
        mock_channel = double('channel')
        mock_exchange = double('default_exchange')
        mock_channel_pool = double('channel_pool')

        allow(mock_channel_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
        allow(mock_exchange).to receive(:publish)
        $rmq_channel_pool = mock_channel_pool

        result = publisher.enqueue_transient(:domain_verified, { domain: 'example.com' })

        expect(result).to be true
        expect(mock_exchange).to have_received(:publish)
          .with(satisfy { |p| JSON.parse(p, symbolize_names: true)[:event_type] == 'domain_verified' }, anything)

        $rmq_channel_pool = nil
      end

      it 'coerces non-hash data to empty hash' do
        mock_channel = double('channel')
        mock_exchange = double('default_exchange')
        mock_channel_pool = double('channel_pool')

        allow(mock_channel_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
        allow(mock_exchange).to receive(:publish)
        $rmq_channel_pool = mock_channel_pool

        result = publisher.enqueue_transient('domain.verified', 'not a hash')

        expect(result).to be true
        expect(mock_exchange).to have_received(:publish)
          .with(satisfy { |p| JSON.parse(p, symbolize_names: true)[:data] == {} }, anything)

        $rmq_channel_pool = nil
      end

      it 'coerces nil data to empty hash' do
        mock_channel = double('channel')
        mock_exchange = double('default_exchange')
        mock_channel_pool = double('channel_pool')

        allow(mock_channel_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
        allow(mock_exchange).to receive(:publish)
        $rmq_channel_pool = mock_channel_pool

        result = publisher.enqueue_transient('domain.verified', nil)

        expect(result).to be true
        expect(mock_exchange).to have_received(:publish)
          .with(satisfy { |p| JSON.parse(p, symbolize_names: true)[:data] == {} }, anything)

        $rmq_channel_pool = nil
      end
    end

    context 'with RabbitMQ' do
      let(:mock_channel) { double('channel') }
      let(:mock_exchange) { double('default_exchange') }
      let(:mock_channel_pool) { double('channel_pool') }

      before do
        allow(mock_channel_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
        allow(mock_exchange).to receive(:publish)
        $rmq_channel_pool = mock_channel_pool
      end

      after do
        $rmq_channel_pool = nil
      end

      it 'returns true when successfully published' do
        result = publisher.enqueue_transient('domain.verified', { domain: 'example.com' })

        expect(result).to be true
      end

      it 'publishes to system.transient queue' do
        publisher.enqueue_transient('domain.verified', { domain: 'example.com' })

        expect(mock_exchange).to have_received(:publish)
          .with(anything, hash_including(routing_key: 'system.transient'))
      end

      it 'publishes non-persistent messages' do
        publisher.enqueue_transient('domain.verified', { domain: 'example.com' })

        expect(mock_exchange).to have_received(:publish)
          .with(anything, hash_including(persistent: false))
      end

      it 'includes event_type in payload' do
        publisher.enqueue_transient('domain.verified', { domain: 'example.com' })

        expect(mock_exchange).to have_received(:publish)
          .with(satisfy { |p| JSON.parse(p, symbolize_names: true)[:event_type] == 'domain.verified' }, anything)
      end

      it 'includes data in payload' do
        publisher.enqueue_transient('domain.verified', { domain: 'example.com', org_id: 'abc123' })

        expect(mock_exchange).to have_received(:publish)
          .with(satisfy { |p| JSON.parse(p, symbolize_names: true)[:data] == { domain: 'example.com', org_id: 'abc123' } }, anything)
      end

      it 'includes timestamp in payload' do
        publisher.enqueue_transient('domain.verified', {})

        expect(mock_exchange).to have_received(:publish)
          .with(satisfy { |p| JSON.parse(p, symbolize_names: true)[:timestamp] =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/ }, anything)
      end

      it 'swallows errors and returns false' do
        allow(mock_exchange).to receive(:publish).and_raise(StandardError, 'Connection lost')

        result = publisher.enqueue_transient('domain.verified', {})

        expect(result).to be false
      end
    end
  end
end
