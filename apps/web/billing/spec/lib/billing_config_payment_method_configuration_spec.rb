# apps/web/billing/spec/lib/billing_config_payment_method_configuration_spec.rb
#
# frozen_string_literal: true

# Resolution rules for the Stripe payment-method-configuration pin (pmc_...):
# ENV['STRIPE_PAYMENT_METHOD_CONFIGURATION'] first, then billing.yaml
# 'payment_method_configuration', default nil (Dashboard default applies).
# Blank/whitespace-only values are treated as unset. Subtlety: a blank-but-set
# ENV value is truthy through the `||`, so it does NOT fall back to the yaml
# key — blank ENV means explicitly unset. ENV access is stubbed (never
# mutated) so nothing leaks between examples.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_payment_method_configuration_spec.rb

require_relative '../support/billing_spec_helper'

RSpec.describe Onetime::BillingConfig, '#payment_method_configuration' do
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
  end

  it 'returns nil when neither ENV nor config set it (Dashboard default)' do
    expect(billing_config.payment_method_configuration).to be_nil
  end

  it "returns the ENV value when ENV['STRIPE_PAYMENT_METHOD_CONFIGURATION'] is set" do
    stub_env('pmc_env_123')
    expect(billing_config.payment_method_configuration).to eq('pmc_env_123')
  end

  it 'falls back to the config file key when ENV is unset' do
    stub_config('payment_method_configuration' => 'pmc_yaml_456')
    expect(billing_config.payment_method_configuration).to eq('pmc_yaml_456')
  end

  it 'lets ENV override the config file key' do
    stub_env('pmc_env_123')
    stub_config('payment_method_configuration' => 'pmc_yaml_456')
    expect(billing_config.payment_method_configuration).to eq('pmc_env_123')
  end

  it 'treats a blank ENV value as unset' do
    stub_env('')
    expect(billing_config.payment_method_configuration).to be_nil
  end

  it 'treats a whitespace-only ENV value as unset' do
    stub_env('   ')
    expect(billing_config.payment_method_configuration).to be_nil
  end

  # A blank ENV value is truthy through the `||`, so it masks the yaml key
  # rather than falling back to it: setting the var to '' explicitly unsets
  # the pin for that deployment even when billing.yaml carries one.
  it 'does NOT fall back to the config file key when ENV is blank' do
    stub_env('')
    stub_config('payment_method_configuration' => 'pmc_yaml_456')
    expect(billing_config.payment_method_configuration).to be_nil
  end

  it 'treats a blank config file value as unset' do
    stub_config('payment_method_configuration' => '   ')
    expect(billing_config.payment_method_configuration).to be_nil
  end

  it 'strips surrounding whitespace from the resolved value' do
    stub_env("  pmc_padded_789\n")
    expect(billing_config.payment_method_configuration).to eq('pmc_padded_789')
  end
end
