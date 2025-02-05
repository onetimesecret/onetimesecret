# tests/unit/ruby/rspec/onetime/config_spec.rb

require_relative '../spec_helper'

RSpec.describe Onetime::Config do
  describe '#merge_config_sections' do
    let(:config_with_defaults) do
      {
        defaults: { timeout: 5, enabled: true },
        api: { timeout: 10 },
        web: {}
      }
    end

    let(:empty_config) { {} }
    let(:nil_config) { nil }

    let(:service_config) do
      {
        defaults: { dsn: 'default-dsn', environment: 'test' },
        backend: { dsn: 'backend-dsn' },
        frontend: { path: '/web' }
      }
    end

    it 'merges defaults into sections while preserving overrides' do
      result = described_class.merge_config_sections(config_with_defaults)

      expect(result[:api]).to eq({ timeout: 10, enabled: true })
      expect(result[:web]).to eq({ timeout: 5, enabled: true })
    end

    it 'handles empty config' do
      result = described_class.merge_config_sections(empty_config)
      expect(result).to eq({})
    end

    it 'handles nil config' do
      result = described_class.merge_config_sections(nil_config)
      expect(result).to eq({})
    end

    it 'processes real world service config correctly' do
      result = described_class.merge_config_sections(service_config)

      expect(result[:backend]).to eq({
        dsn: 'backend-dsn',
        environment: 'test'
      })

      expect(result[:frontend]).to eq({
        dsn: 'default-dsn',
        environment: 'test',
        path: '/web'
      })
    end

    it 'preserves original defaults hash' do
      original_defaults = service_config[:defaults].dup
      described_class.merge_config_sections(service_config)

      expect(service_config[:defaults]).to eq(original_defaults)
    end
  end
end
