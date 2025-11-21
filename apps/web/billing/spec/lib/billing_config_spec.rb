# frozen_string_literal: true

require 'spec_helper'
require 'onetime'

RSpec.describe Onetime::BillingConfig do
  describe 'when config file does not exist' do
    let(:config) { described_class.instance }

    it 'loads with empty config' do
      expect(config.config).to eq({})
    end

    it 'returns false for enabled?' do
      expect(config.enabled?).to be false
    end

    it 'returns nil for stripe_key' do
      expect(config.stripe_key).to be_nil
    end

    it 'returns nil for webhook_signing_secret' do
      expect(config.webhook_signing_secret).to be_nil
    end

    it 'returns empty hash for payment_links' do
      expect(config.payment_links).to eq({})
    end
  end
end
