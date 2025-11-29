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

    it 'defines email.message.send queue' do
      expect(queues).to have_key('email.message.send')
    end

    it 'defines email.message.schedule queue' do
      expect(queues).to have_key('email.message.schedule')
    end

    it 'defines notifications.alert.push queue' do
      expect(queues).to have_key('notifications.alert.push')
    end

    it 'defines billing.event.process queue' do
      expect(queues).to have_key('billing.event.process')
    end

    it 'defines webhooks.payload.deliver queue' do
      expect(queues).to have_key('webhooks.payload.deliver')
    end

    it 'defines system.transient queue' do
      expect(queues).to have_key('system.transient')
    end

    it 'has 6 queues total' do
      expect(queues.size).to eq(6)
    end
  end

  describe 'email.message.send queue' do
    subject(:queue) { described_class::QUEUES['email.message.send'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.email.message')
    end
  end

  describe 'email.message.schedule queue' do
    subject(:queue) { described_class::QUEUES['email.message.schedule'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has message TTL configured' do
      expect(queue[:arguments]).to have_key('x-message-ttl')
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.email.message')
    end
  end

  describe 'billing.event.process queue' do
    subject(:queue) { described_class::QUEUES['billing.event.process'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.billing.event')
    end
  end

  describe 'notifications.alert.push queue' do
    subject(:queue) { described_class::QUEUES['notifications.alert.push'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.notifications.alert')
    end
  end

  describe 'webhooks.payload.deliver queue' do
    subject(:queue) { described_class::QUEUES['webhooks.payload.deliver'] }

    it 'is durable' do
      expect(queue[:durable]).to be true
    end

    it 'has dead letter exchange configured' do
      expect(queue[:arguments]['x-dead-letter-exchange']).to eq('dlx.webhooks.payload')
    end
  end

  describe 'system.transient queue' do
    subject(:queue) { described_class::QUEUES['system.transient'] }

    it 'is not durable (ephemeral)' do
      expect(queue[:durable]).to be false
    end

    it 'has auto_delete enabled' do
      expect(queue[:auto_delete]).to be true
    end

    it 'has message TTL configured (5 minutes)' do
      expect(queue[:arguments]['x-message-ttl']).to eq(300_000)
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

  describe 'DEAD_LETTER_CONFIG' do
    subject(:dead_letter_config) { described_class::DEAD_LETTER_CONFIG }

    it 'is a frozen hash' do
      expect(dead_letter_config).to be_frozen
    end

    it 'has 4 entries' do
      expect(dead_letter_config.size).to eq(4)
    end

    it "contains 'dlx.email.message' with queue 'dlq.email.message'" do
      expect(dead_letter_config).to have_key('dlx.email.message')
      expect(dead_letter_config['dlx.email.message'][:queue]).to eq('dlq.email.message')
    end

    it "contains 'dlx.notifications.alert' with queue 'dlq.notifications.alert'" do
      expect(dead_letter_config).to have_key('dlx.notifications.alert')
      expect(dead_letter_config['dlx.notifications.alert'][:queue]).to eq('dlq.notifications.alert')
    end

    it "contains 'dlx.webhooks.payload' with queue 'dlq.webhooks.payload'" do
      expect(dead_letter_config).to have_key('dlx.webhooks.payload')
      expect(dead_letter_config['dlx.webhooks.payload'][:queue]).to eq('dlq.webhooks.payload')
    end

    it "contains 'dlx.billing.event' with queue 'dlq.billing.event'" do
      expect(dead_letter_config).to have_key('dlx.billing.event')
      expect(dead_letter_config['dlx.billing.event'][:queue]).to eq('dlq.billing.event')
    end
  end

  describe 'IDEMPOTENCY_TTL' do
    it 'is defined as 3600' do
      expect(described_class::IDEMPOTENCY_TTL).to eq(3600)
    end
  end
end
