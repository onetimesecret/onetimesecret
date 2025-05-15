# tests/unit/ruby/rspec/onetime/config/file_loading_spec.rb

require_relative '../../spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Onetime::Config do
  let(:temp_dir) { Dir.mktmpdir('onetime_config_test') }
  let(:test_config_path) { File.join(temp_dir, 'config.yaml') }
  let(:valid_yaml) do
    <<~YAML
      ---
      :site:
        :host: example.com
        :ssl: true
        :secret: <%= ENV['SECRET'] || 'test_secret' %>
        :authentication:
          :enabled: true
          :signup: true
      :redis:
        :uri: redis://localhost:6379/0
      :mail:
        :truemail:
          :default_validation_type: :regex
      :development:
        :enabled: false
    YAML
  end

  before do
    # Store original state
    @original_path = described_class.instance_variable_get(:@path)
    @original_dirname = described_class.instance_variable_get(:@dirname)
    @original_mode = Onetime.mode

    # Create test directory and files
    FileUtils.mkdir_p(temp_dir)
    File.write(test_config_path, valid_yaml)

    # Suppress logs during tests
    allow(Onetime).to receive(:ld)
    allow(Onetime).to receive(:le)
  end

  after do
    # Restore original state
    described_class.instance_variable_set(:@path, @original_path)
    described_class.instance_variable_set(:@dirname, @original_dirname)
    Onetime.mode = @original_mode

    # Clean up test directory
    FileUtils.remove_entry(temp_dir)
  end

  describe '.load' do
    context 'with a valid configuration file' do
      it 'loads and parses YAML successfully' do
        config = described_class.load(test_config_path)

        expect(config).to be_a(Hash)
        expect(config[:site][:host]).to eq('example.com')
        expect(config[:site][:ssl]).to eq(true)
        expect(config[:site][:authentication][:enabled]).to eq(true)
      end

      it 'processes ERB templates in the configuration' do
        # Set environment variable for testing
        allow(ENV).to receive(:[]).with('SECRET').and_return('env_secret')

        config = described_class.load(test_config_path)

        expect(config[:site][:secret]).to eq('env_secret')
      end

      it 'falls back to default value in ERB when environment variable is not set' do
        # Ensure environment variable is not set
        allow(ENV).to receive(:[]).with('SECRET').and_return(nil)

        config = described_class.load(test_config_path)

        expect(config[:site][:secret]).to eq('test_secret')
      end
    end

    context 'with invalid configuration files' do
      it 'uses a default path when given nil' do
        expect(described_class.load(nil)).to be_a(Hash)
        expect(described_class.path).to be_a(String)
      end

      it 'raises ArgumentError for unreadable file' do
        nonexistent_path = '/path/does/not/exist.yaml'
        expect { described_class.load(nonexistent_path) }.to raise_error(OT::ConfigError, /Bad path/)
      end

      it 'exits with error for invalid YAML' do
        invalid_yaml_path = File.join(temp_dir, 'invalid.yaml')
        File.write(invalid_yaml_path, "---\n:site: *undefined_alias\n")

        expect(Onetime).to receive(:le).at_least(:once)
        expect { described_class.load(invalid_yaml_path) }.to raise_error(OT::ConfigError)
      end

      it 'exits with error for invalid ERB' do
        invalid_erb_path = File.join(temp_dir, 'invalid_erb.yaml')
        File.write(invalid_erb_path, "---\n:site:\n  :host: <%= undefined_method %>\n")

        expect(Onetime).to receive(:le).at_least(:once)
        expect { described_class.load(invalid_erb_path) }.to raise_error(OT::ConfigError)
      end
    end
  end

  describe '.path' do
    context 'when path is already set' do
      it 'returns the cached path' do
        described_class.instance_variable_set(:@path, '/cached/path')
        expect(described_class.path).to eq('/cached/path')
      end
    end

    context 'when path is not set' do
      before do
        described_class.instance_variable_set(:@path, nil)
      end

      it 'finds config files based on mode' do
        expect(described_class).to receive(:find_configs).and_return(['/found/config.yaml'])
        expect(described_class.path).to eq('/found/config.yaml')
      end

      it 'returns nil when no config files are found' do
        expect(described_class).to receive(:find_configs).and_return([])
        expect(described_class.path).to be_nil
      end
    end
  end

  describe '.find_configs' do
    let(:service_paths) { ['/etc/onetime', './etc'] }
    let(:utility_paths) { ['~/.onetime', '/etc/onetime', './etc'] }

    context 'in service mode' do
      before do
        Onetime.mode = :app
      end

      it 'checks service paths' do
        # Setup expanded paths that will be checked
        expanded_paths = service_paths.map { |p| File.expand_path(File.join(p, 'config.yaml')) }

        # Expect file existence check for each expanded path
        expanded_paths.each do |path|
          expect(File).to receive(:exist?).with(path).and_return(false)
        end

        described_class.find_configs
      end

      it 'returns existing config files' do
        # Create test file in one of the paths
        etc_dir = File.join(temp_dir, 'etc')
        FileUtils.mkdir_p(etc_dir)
        test_file = File.join(etc_dir, 'config.yaml')

        # Write test configuration to the file
        File.write(test_file, valid_yaml)

        # Make sure the file exists
        expect(File.exist?(test_file)).to be true

        # Stub the constant to include our test directory
        stub_const('Onetime::Config::SERVICE_PATHS', [etc_dir])

        result = described_class.find_configs
        expect(result).to eq([test_file])
      end
    end

    context 'in CLI mode' do
      before do
        Onetime.mode = :cli
      end

      it 'checks utility paths' do
        # Setup expanded paths that will be checked
        expanded_paths = utility_paths.map { |p| File.expand_path(File.join(p, 'config.yaml')) }

        # Expect file existence check for each expanded path
        expanded_paths.each do |path|
          expect(File).to receive(:exist?).with(path).and_return(false)
        end

        described_class.find_configs
      end

      it 'supports custom filename' do
        custom_filename = 'custom_config.yaml'

        # Setup expanded paths with custom filename
        expanded_paths = utility_paths.map { |p| File.expand_path(File.join(p, custom_filename)) }

        # Expect file existence check for each expanded path with custom filename
        expanded_paths.each do |path|
          expect(File).to receive(:exist?).with(path).and_return(false)
        end

        described_class.find_configs(custom_filename)
      end
    end
  end

  describe '.dirname' do
    it 'returns the directory name of the config path' do
      described_class.instance_variable_set(:@path, '/path/to/config.yaml')
      expect(described_class.dirname).to eq('/path/to')
    end

    it 'caches the dirname after first call' do
      described_class.instance_variable_set(:@path, '/path/to/config.yaml')
      dirname = described_class.dirname

      # Change path after caching
      described_class.instance_variable_set(:@path, '/different/path/config.yaml')

      # Should still return cached value
      expect(described_class.dirname).to eq(dirname)
    end
  end
end
