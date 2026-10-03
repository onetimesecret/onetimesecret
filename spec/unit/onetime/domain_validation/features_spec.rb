# spec/unit/onetime/domain_validation/features_spec.rb
#
# frozen_string_literal: true

# The validation strategy is configured as free text: Strategy.for_config
# accepts any letter case plus the aliases "caddy" and "external". Clients
# match canonical names only (src/utils/features.ts), so everything that
# leaves Features carries the canonical name of the strategy in effect.

require 'spec_helper'
require 'onetime/domain_validation/strategy'

RSpec.describe Onetime::DomainValidation::Features do
  around do |example|
    saved = %i[strategy_name api_key proxy_ip proxy_host proxy_name vhost_target]
      .to_h { |key| [key, described_class.public_send(key)] }
    example.run
  ensure
    described_class.configure(**saved)
  end

  canonical_by_spelling = {
    'approximated' => 'approximated',
    'Approximated' => 'approximated',
    'passthrough' => 'passthrough',
    'external' => 'passthrough',
    'EXTERNAL' => 'passthrough',
    'caddy_on_demand' => 'caddy_on_demand',
    'Caddy_On_Demand' => 'caddy_on_demand',
    'caddy' => 'caddy_on_demand',
    ' Caddy ' => 'caddy_on_demand',
  }.freeze

  describe '.canonical_strategy_name' do
    canonical_by_spelling.each do |spelling, canonical|
      it "maps #{spelling.inspect} to #{canonical}" do
        expect(described_class.canonical_strategy_name(spelling)).to eq(canonical)
      end
    end

    it 'is nil for a blank or unknown value' do
      expect([nil, '', 'letsencrypt'].map { |raw| described_class.canonical_strategy_name(raw) })
        .to eq([nil, nil, nil])
    end
  end

  describe '.effective_strategy_name' do
    it 'is passthrough for a blank or unknown value, as Strategy.for_config runs it' do
      expect([nil, '', 'letsencrypt'].map { |raw| described_class.effective_strategy_name(raw) })
        .to eq(%w[passthrough passthrough passthrough])
    end

    it 'reads the loaded strategy_name by default' do
      described_class.configure(strategy_name: 'Caddy')
      expect(described_class.effective_strategy_name).to eq('caddy_on_demand')
    end
  end

  describe 'agreement with Strategy.for_config' do
    strategy_classes = {
      'approximated' => 'Onetime::DomainValidation::ApproximatedStrategy',
      'passthrough' => 'Onetime::DomainValidation::PassthroughStrategy',
      'caddy_on_demand' => 'Onetime::DomainValidation::CaddyOnDemandStrategy',
    }

    canonical_by_spelling.each do |spelling, canonical|
      it "builds the #{canonical} strategy for #{spelling.inspect}" do
        config = { 'features' => { 'domains' => { 'validation_strategy' => spelling } } }
        expect(Onetime::DomainValidation::Strategy.for_config(config).class.name)
          .to eq(strategy_classes.fetch(canonical))
      end
    end
  end

  describe '.safe_dump' do
    it 'emits the canonical name for an alias in both strategy fields' do
      described_class.configure(strategy_name: 'caddy', proxy_ip: '203.0.113.10')
      expect(described_class.safe_dump).to include(
        type: 'caddy_on_demand',
        validation_strategy: 'caddy_on_demand',
        proxy_ip: '203.0.113.10',
      )
    end

    it 'emits the canonical name for mixed case and for the external alias' do
      dumps = %w[Approximated External].map do |spelling|
        described_class.configure(strategy_name: spelling)
        described_class.safe_dump.values_at(:type, :validation_strategy)
      end
      expect(dumps).to eq([%w[approximated approximated], %w[passthrough passthrough]])
    end

    it 'emits passthrough for an unknown value' do
      described_class.configure(strategy_name: 'letsencrypt')
      expect(described_class.safe_dump).to include(type: 'passthrough', validation_strategy: 'passthrough')
    end

    it 'keeps type nil while no strategy is loaded' do
      described_class.reset!
      expect(described_class.safe_dump).to include(type: nil, validation_strategy: 'passthrough')
    end

    it 'never includes the API key' do
      described_class.configure(strategy_name: 'approximated', api_key: 'secret-api-key')
      expect(described_class.safe_dump.to_s).not_to include('secret-api-key')
    end
  end

  describe '.approximated?' do
    it 'is true for any letter case and false for the other strategies' do
      results = %w[approximated Approximated caddy passthrough].map do |spelling|
        described_class.configure(strategy_name: spelling)
        described_class.approximated?
      end
      expect(results).to eq([true, true, false, false])
    end
  end
end
