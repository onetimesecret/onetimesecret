# apps/web/billing/spec/lib/billing_config_enabled_spec.rb
#
# frozen_string_literal: true

# Parsing rules for the billing master switch: ENV['BILLING_ENABLED']
# first, then billing.yaml 'enabled', default false. Parsing delegates to
# Onetime::Utils.strict_bool!, so the full shared token vocabulary applies
# (1/true/yes/on/y/t and 0/false/no/off/n/f); blank is explicitly off; any
# other set value raises Onetime::ConfigError — BILLING_ENABLED=1 used to
# silently disable billing. ENV access is stubbed (never mutated) so
# nothing leaks between examples.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/billing_config_enabled_spec.rb

require_relative '../support/billing_spec_helper'

RSpec.describe Onetime::BillingConfig, '#enabled?' do
  subject(:billing_config) { Onetime.billing_config }

  def stub_env(value)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('BILLING_ENABLED', nil).and_return(value)
  end

  def stub_config(hash)
    allow(billing_config).to receive(:config).and_return(hash)
  end

  before do
    stub_env(nil)
    stub_config({})
  end

  it 'defaults to false when neither ENV nor config set it' do
    expect(billing_config.enabled?).to be(false)
  end

  %w[true 1 TRUE].each do |truthy|
    it "is true when ENV['BILLING_ENABLED'] is '#{truthy}'" do
      stub_env(truthy)
      expect(billing_config.enabled?).to be(true)
    end
  end

  %w[false 0].each do |falsy|
    it "is false when ENV['BILLING_ENABLED'] is '#{falsy}', overriding config" do
      stub_env(falsy)
      stub_config('enabled' => true)
      expect(billing_config.enabled?).to be(false)
    end
  end

  # Additional coverage since parsing unified on Onetime::Utils.strict_bool!:
  # the full shared vocabulary is accepted, so BILLING_ENABLED=yes now
  # enables billing instead of raising at boot.
  %w[yes on y t].each do |truthy|
    it "is true when ENV['BILLING_ENABLED'] is '#{truthy}' (shared vocabulary)" do
      stub_env(truthy)
      expect(billing_config.enabled?).to be(true)
    end
  end

  %w[no off n f].each do |falsy|
    it "is false when ENV['BILLING_ENABLED'] is '#{falsy}', overriding config (shared vocabulary)" do
      stub_env(falsy)
      stub_config('enabled' => true)
      expect(billing_config.enabled?).to be(false)
    end
  end

  it 'treats a blank ENV value as explicitly off, not a fallback to config' do
    stub_env('   ')
    stub_config('enabled' => true)
    expect(billing_config.enabled?).to be(false)
  end

  it 'falls back to the config file key when ENV is unset' do
    stub_config('enabled' => true)
    expect(billing_config.enabled?).to be(true)
  end

  it "accepts the config file value as a 'true' string" do
    stub_config('enabled' => 'true')
    expect(billing_config.enabled?).to be(true)
  end

  # 'yes'/'on'/'t' moved out of this table when parsing unified on the
  # shared vocabulary — they are recognized tokens now, asserted above.
  %w[enabled ture 2].each do |bad|
    it "raises ConfigError when ENV['BILLING_ENABLED'] is '#{bad}'" do
      stub_env(bad)
      expect { billing_config.enabled? }
        .to raise_error(Onetime::ConfigError, /BILLING_ENABLED.*#{bad}/)
    end
  end

  it 'raises ConfigError on an arbitrary config file value' do
    stub_config('enabled' => 'maybe')
    expect { billing_config.enabled? }
      .to raise_error(Onetime::ConfigError, /billing\.yaml 'enabled'/)
  end
end
