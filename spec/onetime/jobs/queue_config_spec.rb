# spec/onetime/jobs/queue_config_spec.rb
#
# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/onetime/jobs/queue_config'

RSpec.describe Onetime::Jobs::QueueConfig do
  describe 'QUEUES' do
    subject(:queues) { described_class::QUEUES }

    it 'is a frozen hash' do
      expect(queues).to be_frozen
    end

    it 'defines email.immediate queue' do
      expect(queues).to have_key('email.immediate')
    end

    it 'defines email.scheduled queue' do
      expect(queues).to have_key('email.scheduled')
    end

    it 'defines notifications.push queue' do
      expect(queues).to have_key('notifications.push')
    end

    it 'defines billing.events queue' do
      expect(queues).to have_key('billing.events')
    end

    it 'defines webhooks.deliver queue' do
      expect(queues).to have_key('webhooks.deliver')
    end

    it 'has 5 queues total' do
      expect(queues.size).to eq(5)
    end
  end

  describe 'email.immediate queue' do
    subject(:queue) { described_class::QUEUES['email.immediate'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.email')
    end
  end

  describe 'email.scheduled queue' do
    subject(:queue) { described_class::QUEUES['email.scheduled'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has message TTL configured' do
      expect(queue[:arguments]).to have_key('x-message-ttl')
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.email')
    end
  end

  describe 'billing.events queue' do
    subject(:queue) { described_class::QUEUES['billing.events'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.billing')
    end
  end

  describe 'CURRENT_SCHEMA_VERSION' do
    it 'is defined as 1' do
      expect(described_class::CURRENT_SCHEMA_VERSION).to eq(1)
    end
  end

  describe 'Versions' do
    it 'defines V1 as 1' do
      expect(described_class::Versions::V1).to eq(1)
    end
  end
end
