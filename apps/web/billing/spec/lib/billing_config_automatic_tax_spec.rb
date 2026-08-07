# apps/web/billing/spec/lib/billing_config_automatic_tax_spec.rb
#
# frozen_string_literal: true

# Parsing rules for the deployment-level automatic-tax switch:
# ENV['STRIPE_AUTOMATIC_TAX'] first, then billing.yaml 'automatic_tax',
# default false. 'true'/'1' enable, 'false'/'0' disable, blank is unset;
# any other set value raises Onetime::ConfigError — an unrecognized token
# used to silently disable tax collection on every checkout. ENV access is
# stubbed (never mutated) so nothing leaks between examples.
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

  %w[false 0 FALSE].each do |falsy|
    it "is false when ENV['STRIPE_AUTOMATIC_TAX'] is '#{falsy}'" do
      stub_env(falsy)
      expect(billing_config.automatic_tax?).to be(false)
    end
  end

  it 'treats a blank ENV value as unset (false)' do
    stub_env('   ')
    stub_config('automatic_tax' => true)
    expect(billing_config.automatic_tax?).to be(false)
  end

  %w[yes on enabled t].each do |bad|
    it "raises ConfigError when ENV['STRIPE_AUTOMATIC_TAX'] is '#{bad}'" do
      stub_env(bad)
      expect { billing_config.automatic_tax? }
        .to raise_error(Onetime::ConfigError, /STRIPE_AUTOMATIC_TAX.*#{bad}/)
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

  it 'raises ConfigError on an arbitrary config file value' do
    stub_config('automatic_tax' => 'yes')
    expect { billing_config.automatic_tax? }
      .to raise_error(Onetime::ConfigError, /billing\.yaml 'automatic_tax'/)
  end
end
