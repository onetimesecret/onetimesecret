# apps/web/billing/spec/lib/billing_config_automatic_tax_spec.rb
#
# frozen_string_literal: true

# Parsing rules for the deployment-level automatic-tax switch:
# ENV['STRIPE_AUTOMATIC_TAX'] first, then billing.yaml 'automatic_tax',
# default false. Only 'true'/'1' enable it. ENV access is stubbed (never
# mutated) so nothing leaks between examples.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_automatic_tax_spec.rb

require_relative '../support/billing_spec_helper'

RSpec.describe Onetime::BillingConfig, '#automatic_tax?' do
  subject(:billing_config) { Onetime.billing_config }

  def stub_env(value)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('STRIPE_AUTOMATIC_TAX', nil).and_return(value)
  end

  def stub_config(hash)
    allow(billing_config).to receive(:config).and_return(hash)
  end

  before do
    stub_env(nil)
    stub_config({})
  end

  it 'defaults to false when neither ENV nor config set it' do
    expect(billing_config.automatic_tax?).to be(false)
  end

  %w[true 1].each do |truthy|
    it "is true when ENV['STRIPE_AUTOMATIC_TAX'] is '#{truthy}'" do
      stub_env(truthy)
      expect(billing_config.automatic_tax?).to be(true)
    end
  end

  %w[false 0 yes on enabled].each do |other|
    it "is false when ENV['STRIPE_AUTOMATIC_TAX'] is '#{other}'" do
      stub_env(other)
      expect(billing_config.automatic_tax?).to be(false)
    end
  end

  it 'falls back to the config file key when ENV is unset' do
    stub_config('automatic_tax' => true)
    expect(billing_config.automatic_tax?).to be(true)
  end

  it "accepts the config file value as a 'true' string" do
    stub_config('automatic_tax' => 'true')
    expect(billing_config.automatic_tax?).to be(true)
  end

  it 'lets ENV override a truthy config file value' do
    stub_env('false')
    stub_config('automatic_tax' => true)
    expect(billing_config.automatic_tax?).to be(false)
  end

  it 'treats an arbitrary config file value as false' do
    stub_config('automatic_tax' => 'yes')
    expect(billing_config.automatic_tax?).to be(false)
  end
end
