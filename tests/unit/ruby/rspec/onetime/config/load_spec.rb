# tests/unit/ruby/rspec/onetime/config/load_spec.rb

require_relative '../../spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Onetime::Configurator do
  let(:temp_dir) { Dir.mktmpdir('onetime_config_test') }
  let(:test_config_path) { File.join(temp_dir, 'config.yaml') }
  let(:simple_yaml) do
    <<~YAML
      ---
      site:
        host: example.com
        secret: test_secret
      mail:
        validation:
          default:
            verifier_email: test@example.com
    YAML
  end

  before do
    FileUtils.mkdir_p(temp_dir)
    File.write(test_config_path, simple_yaml)

    # Suppress logs during tests
    allow(Onetime).to receive(:ld)
    allow(Onetime).to receive(:le)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'accepts custom config_path' do
      instance = described_class.new(config_path: test_config_path)

      expect(instance.config_path).to eq(test_config_path)
    end

    it 'finds config automatically when no path provided' do
      instance = described_class.new

      expect(instance.config_path).to be_a(String)
    end
  end

  describe '#load_config' do
    it 'loads YAML configuration from file' do
      instance = described_class.new(config_path: test_config_path)

      # Access the private method for testing
      config = instance.send(:load_config)

      expect(config).to be_a(Hash)
      expect(config['site']['host']).to eq('example.com')
      expect(config['site']['secret']).to eq('test_secret')
    end
  end

  describe 'ERB template processing' do
    let(:erb_yaml) do
      <<~YAML
        ---
        site:
          host: <%= ENV['TEST_HOST'] || 'localhost' %>
          secret: <%= ENV['SECRET'] || 'default_secret' %>
        mail:
          validation:
            default:
              verifier_email: test@example.com
      YAML
    end

    before do
      File.write(test_config_path, erb_yaml)
    end

    it 'processes ERB templates in configuration' do
      ENV['TEST_HOST'] = 'custom.example.com'
      ENV['SECRET'] = 'env_secret'

      instance = described_class.new(config_path: test_config_path)
      config = instance.send(:load_config)

      expect(config['site']['host']).to eq('custom.example.com')
      expect(config['site']['secret']).to eq('env_secret')

      ENV.delete('TEST_HOST')
      ENV.delete('SECRET')
    end

    it 'uses default values when environment variables are not set' do
      ENV.delete('TEST_HOST')
      ENV.delete('SECRET')

      instance = described_class.new(config_path: test_config_path)
      config = instance.send(:load_config)

      expect(config['site']['host']).to eq('localhost')
      expect(config['site']['secret']).to eq('default_secret')
    end
  end

  describe 'error handling' do
    it 'raises error for unreadable file' do
      non_existent_path = File.join(temp_dir, 'nonexistent.yaml')

      expect {
        described_class.new(config_path: non_existent_path).send(:load_config)
      }.to raise_error(ArgumentError, /Configuration file not found/)
    end

    it 'handles invalid YAML gracefully' do
      invalid_yaml = "invalid: yaml: content: ["
      File.write(test_config_path, invalid_yaml)

      expect {
        described_class.new(config_path: test_config_path).send(:load_config)
      }.to raise_error(OT::ConfigError)
    end

    it 'handles invalid ERB gracefully' do
      invalid_erb = "site:\n  host: <%= raise 'ERB error' %>"
      File.write(test_config_path, invalid_erb)

      expect {
        described_class.new(config_path: test_config_path).send(:load_config)
      }.to raise_error(RuntimeError, 'ERB error')
    end
  end

  describe '.find_configs' do
    let(:config_dir) { temp_dir }

    before do
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'config.yaml'), simple_yaml)
      File.write(File.join(config_dir, 'config.yml'), simple_yaml)

      # Mock paths to include our test directory
      allow(described_class).to receive(:paths).and_return([temp_dir])
    end

    it 'finds config files in search paths' do
      configs = described_class.find_configs('config')

      expect(configs.length).to be >= 1
      expect(configs.any? { |c| c.include?('config.yaml') || c.include?('config.yml') }).to be true
    end

    it 'supports custom basename' do
      File.write(File.join(config_dir, 'custom.yaml'), simple_yaml)

      configs = described_class.find_configs('custom')

      expect(configs.any? { |c| c.include?('custom.yaml') }).to be true
    end
  end

  describe '.find_config' do
    let(:config_dir) { temp_dir }

    before do
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'config.yaml'), simple_yaml)

      # Mock paths to include our test directory
      allow(described_class).to receive(:paths).and_return([temp_dir])
    end

    it 'returns first found config file' do
      config_path = described_class.find_config('config')

      expect(config_path).to include('config.yaml')
    end

    it 'returns nil when no config files are found' do
      config_path = described_class.find_config('nonexistent')

      expect(config_path).to be_nil
    end
  end
end
