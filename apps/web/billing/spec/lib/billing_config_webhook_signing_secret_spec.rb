# apps/web/billing/spec/lib/billing_config_webhook_signing_secret_spec.rb
#
# frozen_string_literal: true

# Resolution rules for the Stripe webhook signing secret: the billing.yaml
# key as is, except that a blank value or the 'nosigningsecret' placeholder
# (what older copies of etc/examples/billing.example.yaml fell back to when
# STRIPE_WEBHOOK_SIGNING_SECRET was unset) resolves to nil. An HMAC key that
# is printed in the repository verifies everybody's events, so
# WebhookValidator must see it as "not configured" and refuse the request.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_webhook_signing_secret_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../lib/webhook_validator'

RSpec.describe Onetime::BillingConfig, '#webhook_signing_secret' do
  subject(:billing_config) { Onetime.billing_config }

  def stub_config(hash)
    allow(billing_config).to receive(:config).and_return(hash)
  end

  it 'returns nil when the key is absent' do
    stub_config({})
    expect(billing_config.webhook_signing_secret).to be_nil
  end

  it 'returns the configured value' do
    stub_config('webhook_signing_secret' => 'whsec_configured')
    expect(billing_config.webhook_signing_secret).to eq('whsec_configured')
  end

  ['', '   ', 'nosigningsecret'].each do |not_a_secret|
    it "returns nil when the configured value is #{not_a_secret.inspect}" do
      stub_config('webhook_signing_secret' => not_a_secret)
      expect(billing_config.webhook_signing_secret).to be_nil
    end

    it "makes WebhookValidator refuse to start when the configured value is #{not_a_secret.inspect}" do
      stub_config('webhook_signing_secret' => not_a_secret)
      expect do
        Billing::WebhookValidator.new
      end.to raise_error(ArgumentError, /webhook signing secret/i)
    end
  end
end
