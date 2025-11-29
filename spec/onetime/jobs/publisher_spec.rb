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
    it 'defines MAX_RETRIES as 3' do
      expect(described_class::MAX_RETRIES).to eq(3)
    end

    it 'defines RETRY_DELAY as 0.5' do
      expect(described_class::RETRY_DELAY).to eq(0.5)
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

    context 'when channel pool is not initialized' do
      before do
        $rmq_channel_pool = nil
      end

      it 'falls back to synchronous email when Onetime::Mail is available' do
        allow(Onetime::Mail).to receive(:deliver)

        # Should not raise, should fall back to sync
        publisher.enqueue_email(:welcome, { email: 'test@example.com' })

        expect(Onetime::Mail).to have_received(:deliver)
      end
    end
  end
end
