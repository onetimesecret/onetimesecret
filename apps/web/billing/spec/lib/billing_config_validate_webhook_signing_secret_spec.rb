# apps/web/billing/spec/lib/billing_config_validate_webhook_signing_secret_spec.rb
#
# frozen_string_literal: true

# Boot-time validation for the Stripe webhook signing secret. A blank or
# placeholder secret ('nosigningsecret', 'CHANGEME') is a signing key that
# everybody knows, so WebhookValidator refuses to start with it. This check
# surfaces that state at boot: with a real Stripe API key resolved it raises
# Onetime::ConfigError naming STRIPE_WEBHOOK_SIGNING_SECRET; without one it
# only warns, because billing enabled with no key is a supported state
# (StripeSetup logs and continues) and the validator guard already closes
# the forgery there. ENV access is stubbed (never mutated) so nothing leaks
# between examples.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_validate_webhook_signing_secret_spec.rb

require_relative '../support/billing_spec_helper'

RSpec.describe Onetime::BillingConfig, '#validate_webhook_signing_secret!' do
  subject(:billing_config) { Onetime.billing_config }

  not_a_secret = [nil, '', '   ', 'nosigningsecret', 'CHANGEME']
  not_a_key    = [nil, '', '   ', 'nostripekey', 'CHANGEME']

  def stub_env_key(value)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('STRIPE_API_KEY', nil).and_return(value)
  end

  def stub_config(hash)
    allow(billing_config).to receive(:config).and_return(hash)
  end

  before do
    stub_env_key(nil)
    stub_config({})
    allow(OT).to receive(:lw)
    allow(OT).to receive(:ld)
  end

  context 'with a real Stripe API key in billing.yaml' do
    not_a_secret.each do |secret|
      it "raises and names STRIPE_WEBHOOK_SIGNING_SECRET when the secret is #{secret.inspect}" do
        stub_config('stripe_key' => 'sk_test_deadbeef', 'webhook_signing_secret' => secret)
        expect { billing_config.validate_webhook_signing_secret! }
          .to raise_error(Onetime::ConfigError, /STRIPE_WEBHOOK_SIGNING_SECRET/)
      end
    end

    it 'says the secret is not set when the key is absent' do
      stub_config('stripe_key' => 'sk_test_deadbeef')
      expect { billing_config.validate_webhook_signing_secret! }
        .to raise_error(Onetime::ConfigError, /is not set/)
    end

    it 'names the placeholder it found' do
      stub_config('stripe_key' => 'sk_test_deadbeef', 'webhook_signing_secret' => 'nosigningsecret')
      expect { billing_config.validate_webhook_signing_secret! }
        .to raise_error(Onetime::ConfigError, /placeholder "nosigningsecret"/)
    end

    it 'does not raise or warn for a whsec_ value' do
      stub_config('stripe_key' => 'sk_test_deadbeef', 'webhook_signing_secret' => 'whsec_configured')
      expect { billing_config.validate_webhook_signing_secret! }.not_to raise_error
      expect(OT).not_to have_received(:lw)
    end
  end

  context 'with a real Stripe API key from ENV' do
    before { stub_env_key('sk_live_deadbeef') }

    it 'raises when the secret is unset' do
      expect { billing_config.validate_webhook_signing_secret! }
        .to raise_error(Onetime::ConfigError, /STRIPE_WEBHOOK_SIGNING_SECRET/)
    end

    it 'does not raise for a whsec_ value' do
      stub_config('webhook_signing_secret' => 'whsec_configured')
      expect { billing_config.validate_webhook_signing_secret! }.not_to raise_error
    end
  end

  context 'without a real Stripe API key' do
    not_a_key.each do |key|
      not_a_secret.each do |secret|
        it "warns instead of raising for key #{key.inspect} and secret #{secret.inspect}" do
          stub_config('stripe_key' => key, 'webhook_signing_secret' => secret)
          expect { billing_config.validate_webhook_signing_secret! }.not_to raise_error
          expect(OT).to have_received(:lw).with(a_string_matching(/webhook signing secret .* 500/))
        end
      end
    end

    it 'does not warn for a whsec_ value' do
      stub_config('webhook_signing_secret' => 'whsec_configured')
      billing_config.validate_webhook_signing_secret!
      expect(OT).not_to have_received(:lw)
    end

    it 'treats a placeholder ENV key the same as no key' do
      stub_env_key('nostripekey')
      stub_config('stripe_key' => 'sk_test_in_yaml_is_masked_by_env')
      expect { billing_config.validate_webhook_signing_secret! }.not_to raise_error
      expect(OT).to have_received(:lw)
    end
  end
end
