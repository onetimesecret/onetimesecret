# tests/unit/ruby/rspec/onetime/configurator/load_spec.rb

require_relative '../../../spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Onetime::Configurator do
  let(:temp_dir) { Dir.mktmpdir('onetime_config_test') }
  let(:test_config_path) { File.join(temp_dir, 'config.yaml') }
  let(:test_schema_path) { File.join(temp_dir, 'config.schema.yaml') }

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

  let(:basic_schema) do
    <<~YAML
      ---
      "$schema": "https://json-schema.org/draft/2020-12/schema"
      type: object
      properties:
        site:
          type: object
          properties:
            host:
              type: string
              default: localhost
            secret:
              type: string
          required:
            - secret
        mail:
          type: object
          properties:
            validation:
              type: object
              properties:
                default:
                  type: object
                  properties:
                    verifier_email:
                      type: string
      required:
        - site
    YAML
  end

  before do
    FileUtils.mkdir_p(temp_dir)
    File.write(test_config_path, simple_yaml)
    File.write(test_schema_path, basic_schema)

    # Suppress logs during tests
    allow(Onetime).to receive(:ld)
    allow(Onetime).to receive(:le)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT).to receive(:debug?).and_return(false)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    context 'with custom paths' do
      it 'accepts custom config_path and schema_path' do
        instance = described_class.new(
          config_path: test_config_path,
          schema_path: test_schema_path
        )

        expect(instance.config_path).to eq(test_config_path)
        expect(instance.schema_path).to eq(test_schema_path)
      end
    end

    context 'with automatic path discovery' do
      before do
        # Mock the find_config method to return our test files
        # Need to handle any possible basename that might be passed
        allow(described_class).to receive(:find_config).and_call_original

        allow(described_class).to receive(:find_config)
          .with('config')
          .and_return(test_config_path)

        allow(described_class).to receive(:find_config)
          .with('config.schema')
          .and_return(test_schema_path)

        allow(described_class).to receive(:find_config)
          .with('config.test')
          .and_return(test_config_path)

        allow(described_class).to receive(:find_config)
          .with('config.test.schema')
          .and_return(test_schema_path)
      end

      it 'finds config and schema automatically when no paths provided' do
        instance = described_class.new

        expect(instance.config_path).to eq(test_config_path)
        expect(instance.schema_path).to eq(test_schema_path)
      end
    end
  end

  describe '#load!' do
    let(:configurator) do
      described_class.new(
        config_path: test_config_path,
        schema_path: test_schema_path
      )
    end

    context 'successful loading' do
      it 'loads and validates configuration', :allow_redis do
        result = configurator.load!

        # Verify the load! method returns self
        expect(result).to be(configurator)

        # Access configuration through the public accessor
        config = configurator.configuration

        # Debug: Log the actual structure we got
        puts "DEBUG: Loaded config structure: #{config.inspect}"
        puts "DEBUG: Config class: #{config.class}"
        puts "DEBUG: Site section: #{config['site'].inspect}"

        expect(config).to be_a(Hash)
        expect(config).to be_frozen
        expect(config['site']).to be_a(Hash)
        expect(config['site']['host']).to eq('example.com')
        expect(config['site']['secret']).to eq('test_secret')
        expect(config['mail']['validation']['default']['verifier_email']).to eq('test@example.com')
      end

      it 'applies schema defaults during validation', :allow_redis do
        # Create config without host to test default application
        minimal_yaml = <<~YAML
          ---
          site:
            secret: test_secret
        YAML
        File.write(test_config_path, minimal_yaml)

        configurator.load!
        config = configurator.configuration

        # Debug: Check if defaults were applied
        puts "DEBUG: Default application - host value: #{config['site']['host'].inspect}"
        puts "DEBUG: Full site config: #{config['site'].inspect}"

        expect(config['site']['host']).to eq('localhost') # Schema default
        expect(config['site']['secret']).to eq('test_secret')
      end

      it 'allows configuration access multiple times with consistent results', :allow_redis do
        configurator.load!

        config1 = configurator.configuration
        config2 = configurator.configuration

        # Debug: Verify independence
        puts "DEBUG: Config1 object_id: #{config1.object_id}"
        puts "DEBUG: Config2 object_id: #{config2.object_id}"
        puts "DEBUG: Configs equal: #{config1 == config2}"

        expect(config1).to eq(config2)
        expect(config1.object_id).not_to eq(config2.object_id) # Different objects
        expect(config1).to be_frozen
        expect(config2).to be_frozen
      end
    end

    context 'ERB template processing' do
      let(:erb_yaml) do
        <<~YAML
          ---
          site:
            host: <%= ENV['TEST_HOST'] || 'default.localhost' %>
            secret: <%= ENV['TEST_SECRET'] || 'default_secret' %>
          mail:
            validation:
              default:
                verifier_email: test@<%= ENV['TEST_DOMAIN'] || 'example.com' %>
        YAML
      end

      before do
        File.write(test_config_path, erb_yaml)
      end

      it 'processes ERB templates with environment variables', :allow_redis do
        ENV['TEST_HOST'] = 'custom.example.com'
        ENV['TEST_SECRET'] = 'env_secret'
        ENV['TEST_DOMAIN'] = 'custom.org'

        configurator.load!
        config = configurator.configuration

        # Debug: Log ERB processing results
        puts "DEBUG: ERB processed host: #{config['site']['host']}"
        puts "DEBUG: ERB processed secret: #{config['site']['secret']}"
        puts "DEBUG: ERB processed email: #{config['mail']['validation']['default']['verifier_email']}"

        expect(config['site']['host']).to eq('custom.example.com')
        expect(config['site']['secret']).to eq('env_secret')
        expect(config['mail']['validation']['default']['verifier_email']).to eq('test@custom.org')

        # Cleanup
        ENV.delete('TEST_HOST')
        ENV.delete('TEST_SECRET')
        ENV.delete('TEST_DOMAIN')
      end

      it 'uses ERB default values when environment variables are missing', :allow_redis do
        # Ensure ENV vars are not set
        ENV.delete('TEST_HOST')
        ENV.delete('TEST_SECRET')
        ENV.delete('TEST_DOMAIN')

        configurator.load!
        config = configurator.configuration

        # Debug: Log default value usage
        puts "DEBUG: ERB default host: #{config['site']['host']}"
        puts "DEBUG: ERB default secret: #{config['site']['secret']}"
        puts "DEBUG: ERB default email: #{config['mail']['validation']['default']['verifier_email']}"

        expect(config['site']['host']).to eq('default.localhost')
        expect(config['site']['secret']).to eq('default_secret')
        expect(config['mail']['validation']['default']['verifier_email']).to eq('test@example.com')
      end
    end

    context 'error handling' do
      it 'raises ConfigError for missing config file' do
        non_existent_path = File.join(temp_dir, 'nonexistent.yaml')
        configurator = described_class.new(
          config_path: non_existent_path,
          schema_path: test_schema_path
        )

        expect {
          configurator.load!
        }.to raise_error(OT::ConfigError) do |error|
          # Debug: Log actual error details
          puts "DEBUG: Missing file error message: #{error.message}"
          puts "DEBUG: Missing file error class: #{error.class}"

          expect(error.message).to include("File not found")
          expect(error.message).to include(non_existent_path)
        end
      end

      it 'raises ConfigError for missing schema file' do
        non_existent_schema = File.join(temp_dir, 'nonexistent.schema.yaml')
        configurator = described_class.new(
          config_path: test_config_path,
          schema_path: non_existent_schema
        )

        expect {
          configurator.load!
        }.to raise_error(OT::ConfigError) do |error|
          # Debug: Log schema error details
          puts "DEBUG: Missing schema error message: #{error.message}"
          puts "DEBUG: Missing schema error class: #{error.class}"

          expect(error.message).to include("File not found")
          expect(error.message).to include(non_existent_schema)
        end
      end

      it 'raises ConfigError for invalid YAML syntax' do
        invalid_yaml = "invalid: yaml: content: ["
        File.write(test_config_path, invalid_yaml)

        expect {
          configurator.load!
        }.to raise_error(OT::ConfigError) do |error|
          # Debug: Log YAML parsing error details
          puts "DEBUG: Invalid YAML error message: #{error.message}"
          puts "DEBUG: Invalid YAML error class: #{error.class}"

          expect(error.message).to include("Invalid YAML schema")
        end
      end

      it 'raises ConfigError for invalid YAML schema syntax', :allow_redis do
        invalid_schema = "invalid: yaml: content: ["
        File.write(test_schema_path, invalid_schema)

        expect {
          configurator.load!
        }.to raise_error(OT::ConfigError) do |error|
          # Debug: Log schema parsing error details
          puts "DEBUG: Invalid schema error message: #{error.message}"
          puts "DEBUG: Invalid schema error class: #{error.class}"

          expect(error.message).to include("Invalid YAML schema")
        end
      end

      it 'raises error for ERB template errors' do
        invalid_erb = <<~YAML
          ---
          site:
            host: <%= raise 'ERB processing failed' %>
            secret: test_secret
        YAML
        File.write(test_config_path, invalid_erb)

        expect {
          configurator.load!
        }.to raise_error(OT::ConfigError) do |error|
          # Debug: Log ERB error details
          puts "DEBUG: ERB error message: #{error.message}"
          puts "DEBUG: ERB error class: #{error.class}"

          expect(error.message).to include("Unhandled error")
        end
      end

      it 'raises ConfigValidationError for schema validation failures' do
        # Config missing required 'secret' field
        invalid_config = <<~YAML
          ---
          site:
            host: example.com
            # missing required 'secret' field
        YAML
        File.write(test_config_path, invalid_config)

        expect {
          configurator.load!
        }.to raise_error(OT::ConfigValidationError) do |error|
          # Debug: Log validation error details
          puts "DEBUG: Validation error message: #{error.message}"
          puts "DEBUG: Validation error class: #{error.class}"
          puts "DEBUG: Validation error messages: #{error.messages.inspect}"
          puts "DEBUG: Validation error paths: #{error.paths.inspect}"

          expect(error.messages).to be_an(Array)
          expect(error.paths).to be_a(Hash)
          expect(error.message).to include("required")
        end
      end
    end
  end

  describe '#configuration accessor' do
    let(:configurator) do
      described_class.new(
        config_path: test_config_path,
        schema_path: test_schema_path
      )
    end

    it 'returns frozen configuration after loading', :allow_redis do
      configurator.load!
      config = configurator.configuration

      # Debug: Check freezing behavior
      puts "DEBUG: Config frozen: #{config.frozen?}"
      puts "DEBUG: Site section frozen: #{config['site'].frozen?}"
      puts "DEBUG: Site section class: #{config['site'].class}"

      # The configuration accessor returns a frozen copy at the top level
      expect(config).to be_frozen

      # Test that we can't modify the top-level hash
      expect {
        config['new_key'] = 'new_value'
      }.to raise_error(FrozenError)

      # Test behavior of nested objects - they should be immutable through cloning
      # Even if nested objects aren't frozen, modifications shouldn't persist
      # because each call to configuration returns a fresh deep clone
      original_host = config['site']['host']
      config['site']['host'] = 'modified' unless config['site'].frozen?

      # Get a fresh copy and verify it hasn't changed
      fresh_config = configurator.configuration
      expect(fresh_config['site']['host']).to eq(original_host)
    end

    it 'returns deep clones on each access', :allow_redis do
      configurator.load!

      config1 = configurator.configuration
      config2 = configurator.configuration

      # Same content, different objects
      expect(config1).to eq(config2)
      expect(config1.object_id).not_to eq(config2.object_id)
      expect(config1['site'].object_id).not_to eq(config2['site'].object_id)
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

      # Debug: Log found configs
      puts "DEBUG: Found configs: #{configs.inspect}"
      puts "DEBUG: Configs count: #{configs.length}"

      expect(configs.length).to be >= 1
      expect(configs.any? { |c| c.include?('config.yaml') || c.include?('config.yml') }).to be true
    end

    it 'supports custom basename' do
      File.write(File.join(config_dir, 'custom.yaml'), simple_yaml)

      configs = described_class.find_configs('custom')

      # Debug: Log custom configs
      puts "DEBUG: Custom configs found: #{configs.inspect}"

      expect(configs.any? { |c| c.include?('custom.yaml') }).to be true
    end

    it 'returns empty array when no configs found' do
      configs = described_class.find_configs('nonexistent')

      # Debug: Log empty result
      puts "DEBUG: Nonexistent configs: #{configs.inspect}"

      expect(configs).to eq([])
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

      # Debug: Log found path
      puts "DEBUG: First found config: #{config_path.inspect}"

      expect(config_path).to include('config.yaml')
      expect(File.exist?(config_path)).to be true
    end

    it 'returns nil when no config files are found' do
      config_path = described_class.find_config('nonexistent')

      # Debug: Log nil result
      puts "DEBUG: Nonexistent config result: #{config_path.inspect}"

      expect(config_path).to be_nil
    end
  end

  describe 'integration with after_load callback' do
    let(:configurator) do
      described_class.new(
        config_path: test_config_path,
        schema_path: test_schema_path
      )
    end

    it 'executes callback during load process', :allow_redis do
      callback_executed = false
      original_host = nil
      modified_host = nil

      configurator.load! do |config|
        callback_executed = true
        original_host = config['site']['host']

        # Modify config in callback
        config['site']['host'] = 'callback-modified.com'
        modified_host = config['site']['host']

        # Debug: Log callback execution
        puts "DEBUG: Callback executed with original host: #{original_host}"
        puts "DEBUG: Callback modified host to: #{modified_host}"

        config
      end

      final_config = configurator.configuration

      # Debug: Log final results
      puts "DEBUG: Callback executed: #{callback_executed}"
      puts "DEBUG: Final config host: #{final_config['site']['host']}"

      expect(callback_executed).to be true
      expect(original_host).to eq('example.com')
      expect(modified_host).to eq('callback-modified.com')
      expect(final_config['site']['host']).to eq('callback-modified.com')
    end
  end
end
