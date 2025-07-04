# spec/rsfc/configuration_spec.rb

require 'spec_helper'

RSpec.describe RSFC::Configuration do
  describe '#initialize' do
    subject { described_class.new }

    it 'sets default values' do
      expect(subject.default_locale).to eq('en')
      expect(subject.app_environment).to eq('development')
      expect(subject.development_enabled).to be(false)
      expect(subject.template_paths).to eq([])
      expect(subject.features).to eq({})
    end
  end

  describe '#api_base_url' do
    subject { described_class.new }

    context 'when api_base_url is explicitly set' do
      before { subject.api_base_url = 'https://custom.api.com' }

      it 'returns the explicit value' do
        expect(subject.api_base_url).to eq('https://custom.api.com')
      end
    end

    context 'when site configuration is provided' do
      before do
        subject.site_host = 'example.com'
        subject.site_ssl_enabled = true
      end

      it 'builds URL from site configuration' do
        expect(subject.api_base_url).to eq('https://example.com/api')
      end
    end

    context 'when no site host is configured' do
      it 'returns nil' do
        expect(subject.api_base_url).to be_nil
      end
    end
  end

  describe '#development?' do
    subject { described_class.new }

    context 'when development_enabled is true' do
      before { subject.development_enabled = true }

      it 'returns true' do
        expect(subject.development?).to be(true)
      end
    end

    context 'when app_environment is development' do
      before { subject.app_environment = 'development' }

      it 'returns true' do
        expect(subject.development?).to be(true)
      end
    end

    context 'when neither condition is met' do
      before do
        subject.development_enabled = false
        subject.app_environment = 'production'
      end

      it 'returns false' do
        expect(subject.development?).to be(false)
      end
    end
  end

  describe '#feature_enabled?' do
    subject { described_class.new }

    before { subject.features = { 'dark_mode' => true, 'beta_features' => false } }

    it 'returns true for enabled features' do
      expect(subject.feature_enabled?(:dark_mode)).to be(true)
      expect(subject.feature_enabled?('dark_mode')).to be(true)
    end

    it 'returns false for disabled features' do
      expect(subject.feature_enabled?(:beta_features)).to be(false)
      expect(subject.feature_enabled?('beta_features')).to be(false)
    end

    it 'returns false for undefined features' do
      expect(subject.feature_enabled?(:undefined)).to be(false)
    end
  end

  describe '#validate!' do
    subject { described_class.new }

    context 'with valid configuration' do
      it 'does not raise an error' do
        expect { subject.validate! }.not_to raise_error
      end
    end

    context 'with empty locale' do
      before { subject.default_locale = '' }

      it 'raises ConfigurationError' do
        expect { subject.validate! }.to raise_error(RSFC::Configuration::ConfigurationError)
      end
    end

    context 'with negative cache TTL' do
      before { subject.cache_ttl = -1 }

      it 'raises ConfigurationError' do
        expect { subject.validate! }.to raise_error(RSFC::Configuration::ConfigurationError)
      end
    end
  end
end

RSpec.describe RSFC do
  describe '.configure' do
    before { RSFC.reset_configuration! }

    it 'yields configuration object' do
      expect { |b| RSFC.configure(&b) }.to yield_with_args(RSFC::Configuration)
    end

    it 'validates and freezes configuration' do
      config = RSFC.configure do |c|
        c.default_locale = 'es'
      end

      expect(config).to be_frozen
      expect(config.default_locale).to eq('es')
    end
  end

  describe '.configuration' do
    it 'returns configuration instance' do
      expect(RSFC.configuration).to be_a(RSFC::Configuration)
    end

    it 'returns same instance on multiple calls' do
      config1 = RSFC.configuration
      config2 = RSFC.configuration
      expect(config1).to be(config2)
    end
  end

  describe '.reset_configuration!' do
    it 'resets configuration' do
      original_config = RSFC.configuration
      RSFC.reset_configuration!
      new_config = RSFC.configuration
      expect(new_config).not_to be(original_config)
    end
  end
end