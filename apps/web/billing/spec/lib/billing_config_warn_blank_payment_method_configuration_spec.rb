# apps/web/billing/spec/lib/billing_config_warn_blank_payment_method_configuration_spec.rb
#
# frozen_string_literal: true

# Boot-time warning for a blank-but-set payment method configuration.
# A blank ENV['STRIPE_PAYMENT_METHOD_CONFIGURATION'] masks any billing.yaml
# 'payment_method_configuration' value (it does NOT fall back), so the pin
# is silently dropped and checkout reverts to the Stripe Dashboard default.
# warn_blank_payment_method_configuration! surfaces that at boot; it must
# only ever warn, never raise. ENV access is stubbed (never mutated) so
# nothing leaks between examples.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_warn_blank_payment_method_configuration_spec.rb

require_relative '../support/billing_spec_helper'

RSpec.describe Onetime::BillingConfig, '#warn_blank_payment_method_configuration!' do
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

  it 'logs nothing when neither ENV nor config set it' do
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).not_to have_received(:lw)
  end

  it 'logs nothing for a valid ENV value' do
    stub_env('pmc_env_123')
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).not_to have_received(:lw)
  end

  it 'logs nothing for a valid config file value' do
    stub_config('payment_method_configuration' => 'pmc_yaml_456')
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).not_to have_received(:lw)
  end

  # Case (a): the important one — a blank ENV var silently drops the yaml pin.
  it 'warns that a blank ENV value is masking a configured yaml value' do
    stub_env('')
    stub_config('payment_method_configuration' => 'pmc_yaml_456')
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).to have_received(:lw).with(a_string_matching(/masking.*pmc_yaml_456.*Dashboard default/m))
  end

  it 'treats a whitespace-only ENV value as blank for the masking warning' do
    stub_env('   ')
    stub_config('payment_method_configuration' => 'pmc_yaml_456')
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).to have_received(:lw).with(a_string_matching(/masking/))
  end

  # Case (b): blank-but-set with nothing to mask still deserves a heads-up.
  it 'warns that a blank ENV value (with no yaml value) is treated as unset' do
    stub_env('')
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).to have_received(:lw).with(a_string_matching(/blank and treated as unset/))
    expect(OT).not_to have_received(:lw).with(a_string_matching(/masking/))
  end

  it 'warns that a blank-but-present yaml value is treated as unset' do
    stub_config('payment_method_configuration' => '   ')
    billing_config.warn_blank_payment_method_configuration!
    expect(OT).to have_received(:lw).with(a_string_matching(/blank and treated as unset/))
  end

  it 'never raises, regardless of input shape' do
    stub_env('')
    stub_config('payment_method_configuration' => nil)
    expect { billing_config.warn_blank_payment_method_configuration! }.not_to raise_error
  end
end
