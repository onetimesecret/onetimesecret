# apps/web/billing/spec/initializers/stripe_setup_spec.rb
#
# frozen_string_literal: true

# StripeSetup surfaces the resolved automatic-tax policy at boot. Validation
# (automatic_tax? raising on a malformed token) only catches a *malformed*
# value; the accessor defaults to false, so an unset var silently disables tax
# collection. The boot-time log — parallel to the skip_paths boot-log — makes a
# deployment that isn't collecting VAT/GST visible instead of silent
# (security-audit-2026-08-06 finding #1).
#
# Run: pnpm run test:rspec apps/web/billing/spec/initializers/stripe_setup_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../initializers/stripe_setup'

RSpec.describe Billing::Initializers::StripeSetup do
  let(:initializer) { described_class.new }
  let(:logger) { instance_double(SemanticLogger::Logger, debug: nil, info: nil, warn: nil, error: nil) }

  let(:billing_config) do
    instance_double(
      Onetime::BillingConfig,
      enabled?: true,
      validate_checkout_host!: nil,
      validate_payment_method_configuration!: nil,
      automatic_tax?: automatic_tax_enabled,
      stripe_key: 'sk_test_deadbeefcafef00d',
      stripe_api_version: '2025-03-31',
    )
  end
  let(:automatic_tax_enabled) { false }

  before do
    allow(Onetime).to receive(:billing_config).and_return(billing_config)
    allow(Onetime).to receive(:billing_logger).and_return(logger)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    # require 'stripe' at the tail of execute; keep the setter no-ops harmless.
    allow(Stripe).to receive(:api_key=)
    allow(Stripe).to receive(:api_version=)
  end

  describe '#execute — automatic tax policy log' do
    context 'when the switch comes from ENV' do
      before { allow(ENV).to receive(:[]).with('STRIPE_AUTOMATIC_TAX').and_return('true') }

      let(:automatic_tax_enabled) { true }

      it 'logs enabled: true with the ENV source' do
        expect(logger).to receive(:info).with(
          'Stripe automatic tax policy',
          { enabled: true, source: 'ENV STRIPE_AUTOMATIC_TAX' },
        )
        initializer.execute(nil)
      end
    end

    context 'when ENV is unset (falls back to billing.yaml)' do
      before { allow(ENV).to receive(:[]).with('STRIPE_AUTOMATIC_TAX').and_return(nil) }

      it 'logs the disabled default with the config-file source' do
        expect(logger).to receive(:info).with(
          'Stripe automatic tax policy',
          { enabled: false, source: "billing.yaml 'automatic_tax'" },
        )
        initializer.execute(nil)
      end
    end
  end
end
