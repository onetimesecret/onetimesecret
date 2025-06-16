# tests/unit/ruby/rspec/onetime/config/after_load_spec.rb

require_relative '../../spec_helper'

RSpec.describe "Onetime::Config#after_load" do
  let(:config_instance) { OT::Configurator.new }

  def process_config_with_after_load(raw_config)
    config_instance = OT::Configurator.new
    config_instance.instance_variable_set(:@unprocessed_config, raw_config)
    config_instance.send(:after_load)
  end

  let(:minimal_config) do
    {
      development: { enabled: false },
      mail: { truemail: { default_validation_type: :regex, verifier_email: 'hello@example.com' } },
      site: {
        authentication: { enabled: true },
        host: 'example.com',
        secret: 'test_secret',
      },
      redis: { uri: 'redis://localhost:6379/0' },
    }
  end

  describe 'basic functionality' do
    it 'processes configuration and returns frozen result' do
      processed_config = process_config_with_after_load(minimal_config)

      expect(processed_config).to be_frozen
      expect(processed_config).to be_a(Hash)
    end

    it 'normalizes keys to strings' do
      config_with_symbols = {
        site: { secret: 'test_secret', authentication: { enabled: true } }
      }

      processed_config = process_config_with_after_load(config_with_symbols)

      expect(processed_config.keys).to all(be_a(String))
      expect(processed_config['site'].keys).to all(be_a(String))
    end

    it 'does not modify the original config' do
      original_config = minimal_config.dup
      original_secret = original_config[:site][:secret]

      process_config_with_after_load(original_config)

      expect(original_config[:site][:secret]).to eq(original_secret)
    end
  end

  describe 'critical configuration validation' do
    it 'raises error for nil secret' do
      config = minimal_config.dup
      config[:site][:secret] = nil

      expect { process_config_with_after_load(config) }.to raise_error(OT::Problem, /Global secret cannot be nil/)
    end

    it 'raises error for CHANGEME secret' do
      config = minimal_config.dup
      config[:site][:secret] = 'CHANGEME'

      expect { process_config_with_after_load(config) }.to raise_error(OT::Problem, /Global secret cannot be nil/)
    end

    it 'accepts valid secret' do
      config = minimal_config.dup
      config[:site][:secret] = 'valid_secret_123'

      expect { process_config_with_after_load(config) }.not_to raise_error
    end
  end

  describe 'colonels backwards compatibility' do
    it 'moves root colonels to site.authentication.colonels when auth colonels is nil' do
      config = minimal_config.dup
      config[:colonels] = ['admin@example.com']
      config[:site][:authentication].delete(:colonels) if config[:site][:authentication][:colonels]

      processed_config = process_config_with_after_load(config)

      expect(processed_config['site']['authentication']['colonels']).to eq(['admin@example.com'])
      expect(processed_config.key?('colonels')).to be(false)
    end

    it 'combines root colonels with existing auth colonels' do
      config = minimal_config.dup
      config[:colonels] = ['admin@example.com']
      config[:site][:authentication][:colonels] = ['existing@example.com']

      processed_config = process_config_with_after_load(config)

      expect(processed_config['site']['authentication']['colonels']).to eq(['existing@example.com', 'admin@example.com'])
    end

    it 'handles missing colonels gracefully' do
      config = minimal_config.dup

      processed_config = process_config_with_after_load(config)

      expect(processed_config['site']['authentication']['colonels']).to eq([])
    end
  end

  describe 'authentication settings processing' do
    it 'ensures site.authentication exists' do
      config = minimal_config.dup
      config[:site].delete(:authentication)

      processed_config = process_config_with_after_load(config)

      expect(processed_config['site']['authentication']).to be_a(Hash)
    end

    it 'preserves existing authentication settings' do
      config = minimal_config.dup
      config[:site][:authentication] = { enabled: true, custom_setting: 'value' }

      processed_config = process_config_with_after_load(config)

      expect(processed_config['site']['authentication']['enabled']).to be(true)
      expect(processed_config['site']['authentication']['custom_setting']).to eq('value')
    end
  end
end
