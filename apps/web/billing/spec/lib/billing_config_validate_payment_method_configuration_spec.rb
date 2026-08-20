# apps/web/billing/spec/lib/billing_config_validate_payment_method_configuration_spec.rb
#
# frozen_string_literal: true

# Boot-time validation for the payment method configuration (ADR-033).
# Two deterministic local checks: (1) a resolved value that does not start
# with 'pmc_' raises Onetime::ConfigError naming the offending source —
# ENV vs billing.yaml — instead of failing at a customer's first checkout;
# (2) a blank-but-set value warns (never raises). A blank
# ENV['STRIPE_PAYMENT_METHOD_CONFIGURATION'] masks any billing.yaml
# 'payment_method_configuration' value (it does NOT fall back), so the pin
# is silently dropped and checkout reverts to the Stripe Dashboard default.
# When the value resolves to a real pin, no warning applies — checkout IS
# pinned, whatever a blank lower-precedence source holds. ENV access is
# stubbed (never mutated) so nothing leaks between examples.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_validate_payment_method_configuration_spec.rb

require_relative '../support/billing_spec_helper'

RSpec.describe Onetime::BillingConfig, '#validate_payment_method_configuration!' do
  subject(:billing_config) { Onetime.billing_config }

  def stub_env(value)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('STRIPE_PAYMENT_METHOD_CONFIGURATION', nil).and_return(value)
  end

  def stub_config(hash)
    allow(billing_config).to receive(:config).and_return(hash)
  end

  before do
    stub_env(nil)
    stub_config({})
    allow(OT).to receive(:lw)
  end

  describe 'blank-but-set warnings' do
    it 'logs nothing when neither ENV nor config set it' do
      billing_config.validate_payment_method_configuration!
      expect(OT).not_to have_received(:lw)
    end

    it 'logs nothing for a valid ENV value' do
      stub_env('pmc_env_123')
      billing_config.validate_payment_method_configuration!
      expect(OT).not_to have_received(:lw)
    end

    it 'logs nothing for a valid config file value' do
      stub_config('payment_method_configuration' => 'pmc_yaml_456')
      billing_config.validate_payment_method_configuration!
      expect(OT).not_to have_received(:lw)
    end

    it 'logs nothing when a valid ENV value overrides a valid config file value' do
      stub_env('pmc_env_123')
      stub_config('payment_method_configuration' => 'pmc_yaml_456')
      billing_config.validate_payment_method_configuration!
      expect(OT).not_to have_received(:lw)
    end

    # The value resolves through ENV, so the blank yaml key is irrelevant:
    # checkout IS pinned. This was a false positive before the resolved-nil
    # guard — the elsif branch warned 'Dashboard default' despite the pin.
    it 'logs nothing when a valid ENV value coexists with a blank config file value' do
      stub_env('pmc_env_123')
      stub_config('payment_method_configuration' => '')
      billing_config.validate_payment_method_configuration!
      expect(OT).not_to have_received(:lw)
    end

    # Case (a): the important one — a blank ENV var silently drops the yaml pin.
    it 'warns that a blank ENV value is masking a configured yaml value' do
      stub_env('')
      stub_config('payment_method_configuration' => 'pmc_yaml_456')
      billing_config.validate_payment_method_configuration!
      expect(OT).to have_received(:lw).with(a_string_matching(/masking.*pmc_yaml_456.*Dashboard default/m))
    end

    it 'treats a whitespace-only ENV value as blank for the masking warning' do
      stub_env('   ')
      stub_config('payment_method_configuration' => 'pmc_yaml_456')
      billing_config.validate_payment_method_configuration!
      expect(OT).to have_received(:lw).with(a_string_matching(/masking/))
    end

    # Case (b): blank-but-set with nothing to mask still deserves a heads-up.
    it 'warns that a blank ENV value (with no yaml value) is treated as unset' do
      stub_env('')
      billing_config.validate_payment_method_configuration!
      expect(OT).to have_received(:lw).with(a_string_matching(/blank and treated as unset/))
      expect(OT).not_to have_received(:lw).with(a_string_matching(/masking/))
    end

    it 'warns that a blank ENV value (with a blank yaml value) is treated as unset' do
      stub_env('')
      stub_config('payment_method_configuration' => '   ')
      billing_config.validate_payment_method_configuration!
      expect(OT).to have_received(:lw).with(a_string_matching(/blank and treated as unset/))
      expect(OT).not_to have_received(:lw).with(a_string_matching(/masking/))
    end

    it 'warns that a blank-but-present yaml value is treated as unset' do
      stub_config('payment_method_configuration' => '   ')
      billing_config.validate_payment_method_configuration!
      expect(OT).to have_received(:lw).with(a_string_matching(/blank and treated as unset/))
    end
  end

  describe 'malformed (non-pmc_) values' do
    it 'raises for an ENV value of the wrong ID type, naming the env var' do
      stub_env('price_123')
      expect { billing_config.validate_payment_method_configuration! }
        .to raise_error(Onetime::ConfigError, /STRIPE_PAYMENT_METHOD_CONFIGURATION is "price_123"/)
    end

    it 'raises for a config file value of the wrong ID type, naming the yaml key' do
      stub_config('payment_method_configuration' => 'price_123')
      expect { billing_config.validate_payment_method_configuration! }
        .to raise_error(Onetime::ConfigError, /billing\.yaml 'payment_method_configuration' is "price_123"/)
    end

    it "raises for a bare 'pmc' without the underscore" do
      stub_env('pmc')
      expect { billing_config.validate_payment_method_configuration! }
        .to raise_error(Onetime::ConfigError, /not a payment method configuration ID/)
    end

    it 'raises for an uppercased prefix (the check is case-sensitive, like Stripe IDs)' do
      stub_env('PMC_123')
      expect { billing_config.validate_payment_method_configuration! }
        .to raise_error(Onetime::ConfigError, /not a payment method configuration ID/)
    end

    it 'raises for a random string' do
      stub_env('not-an-id-at-all')
      expect { billing_config.validate_payment_method_configuration! }
        .to raise_error(Onetime::ConfigError, /not a payment method configuration ID/)
    end

    it 'blames ENV when a malformed ENV value overrides a valid yaml value' do
      stub_env('price_123')
      stub_config('payment_method_configuration' => 'pmc_yaml_456')
      expect { billing_config.validate_payment_method_configuration! }
        .to raise_error(Onetime::ConfigError, /STRIPE_PAYMENT_METHOD_CONFIGURATION/)
    end

    it 'does not raise for a valid pmc_... value' do
      stub_env('pmc_1AbC2dEf')
      expect { billing_config.validate_payment_method_configuration! }.not_to raise_error
    end

    it 'does not raise for nil or blank values, regardless of input shape' do
      stub_env('')
      stub_config('payment_method_configuration' => nil)
      expect { billing_config.validate_payment_method_configuration! }.not_to raise_error
    end

    # A blank ENV value collapses the resolution to nil, so a malformed
    # yaml value behind it is never resolved — no raise, masking warn only.
    it 'does not raise when a blank ENV value masks a malformed yaml value' do
      stub_env('')
      stub_config('payment_method_configuration' => 'price_123')
      expect { billing_config.validate_payment_method_configuration! }.not_to raise_error
      expect(OT).to have_received(:lw).with(a_string_matching(/masking/))
    end
  end
end
