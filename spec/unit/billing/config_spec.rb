# spec/unit/billing/config_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::Config module.
#
# Tests safe YAML loading including:
# - Malformed YAML handling (Psych::SyntaxError)
# - Invalid ERB template handling
# - Empty/missing config file handling
#
# Run: pnpm run test:rspec spec/unit/billing/config_spec.rb

require 'spec_helper'
require 'tempfile'

# Load billing config module
require_relative '../../../apps/web/billing/config'

RSpec.describe Billing::Config, billing: true do
  describe '.safe_load_config' do
    let(:temp_file) { Tempfile.new(['billing_test', '.yaml']) }

    after do
      temp_file.close
      temp_file.unlink
    end

    # Helper to stub config_path and config_exists?
    def stub_config_path(path, exists: true)
      allow(described_class).to receive(:config_path).and_return(path)
      allow(described_class).to receive(:config_exists?).and_return(exists)
    end

    context 'with valid YAML' do
      before do
        temp_file.write(<<~YAML)
          schema_version: "1.0"
          plans:
            free_v1:
              name: "Free"
        YAML
        temp_file.rewind
        stub_config_path(temp_file.path)
      end

      it 'returns parsed hash' do
        result = described_class.safe_load_config
        expect(result).to be_a(Hash)
        expect(result['schema_version']).to eq('1.0')
        expect(result['plans']).to include('free_v1')
      end
    end

    context 'with malformed YAML' do
      before do
        temp_file.write(<<~YAML)
          plans:
            free_v1:
              name: "Free
              missing_quote: here
          invalid: [unclosed bracket
        YAML
        temp_file.rewind
        stub_config_path(temp_file.path)
      end

      it 'returns empty hash' do
        result = described_class.safe_load_config
        expect(result).to eq({})
      end

      it 'logs Psych::SyntaxError message' do
        expect { described_class.safe_load_config }.to output(/YAML syntax error in billing config/).to_stderr
      end
    end

    context 'with invalid ERB in YAML' do
      before do
        temp_file.write(<<~YAML)
          plans:
            free_v1:
              name: <%= undefined_method_call %>
        YAML
        temp_file.rewind
        stub_config_path(temp_file.path)
      end

      it 'returns empty hash' do
        result = described_class.safe_load_config
        expect(result).to eq({})
      end

      it 'logs StandardError message' do
        expect { described_class.safe_load_config }.to output(/Failed to load billing config/).to_stderr
      end
    end

    context 'when config file is empty' do
      before do
        temp_file.write('')
        temp_file.rewind
        stub_config_path(temp_file.path)
      end

      it 'returns empty hash (not nil)' do
        result = described_class.safe_load_config
        expect(result).to eq({})
        expect(result).not_to be_nil
      end
    end

    context 'when config file does not exist' do
      before do
        stub_config_path('/nonexistent/path.yaml', exists: false)
      end

      it 'returns empty hash' do
        result = described_class.safe_load_config
        expect(result).to eq({})
      end
    end

    context 'with YAML containing only whitespace' do
      before do
        temp_file.write("   \n\n   \n")
        temp_file.rewind
        stub_config_path(temp_file.path)
      end

      it 'returns empty hash' do
        result = described_class.safe_load_config
        expect(result).to eq({})
      end
    end

    context 'with YAML containing date-like values' do
      before do
        # YAML dates are parsed as Date by default, but safe_load
        # without Date in permitted_classes will error or treat as string
        temp_file.write(<<~YAML)
          schema_version: "1.0"
          plans:
            free_v1:
              created: "2024-01-01"
        YAML
        temp_file.rewind
        stub_config_path(temp_file.path)
      end

      it 'parses quoted date as string' do
        result = described_class.safe_load_config
        expect(result['plans']['free_v1']['created']).to eq('2024-01-01')
      end
    end
  end

  describe '.config_exists?' do
    context 'when config_path returns nil' do
      before do
        allow(described_class).to receive(:config_path).and_return(nil)
      end

      it 'returns falsy' do
        expect(described_class.config_exists?).to be_falsey
      end
    end

    context 'when config_path returns non-existent path' do
      before do
        allow(described_class).to receive(:config_path).and_return('/nonexistent/billing.yaml')
      end

      it 'returns false' do
        expect(described_class.config_exists?).to be false
      end
    end

    context 'when config_path returns existing file' do
      let(:temp_file) { Tempfile.new(['billing_test', '.yaml']) }

      before do
        allow(described_class).to receive(:config_path).and_return(temp_file.path)
      end

      after do
        temp_file.close
        temp_file.unlink
      end

      it 'returns true' do
        expect(described_class.config_exists?).to be true
      end
    end
  end

  describe '.load_entitlements' do
    context 'when safe_load_config returns empty hash' do
      before do
        allow(described_class).to receive(:safe_load_config).and_return({})
      end

      it 'returns empty hash' do
        expect(described_class.load_entitlements).to eq({})
      end
    end

    context 'when entitlements key is missing' do
      before do
        allow(described_class).to receive(:safe_load_config).and_return({ 'plans' => {} })
      end

      it 'returns empty hash' do
        expect(described_class.load_entitlements).to eq({})
      end
    end
  end

  describe '.load_plans' do
    context 'when safe_load_config returns empty hash' do
      before do
        allow(described_class).to receive(:safe_load_config).and_return({})
      end

      it 'returns empty hash' do
        expect(described_class.load_plans).to eq({})
      end
    end

    context 'when plans key is missing' do
      before do
        allow(described_class).to receive(:safe_load_config).and_return({ 'entitlements' => {} })
      end

      it 'returns empty hash' do
        expect(described_class.load_plans).to eq({})
      end
    end
  end

  describe '.load_catalog' do
    context 'when safe_load_config returns empty hash' do
      before do
        allow(described_class).to receive(:safe_load_config).and_return({})
      end

      it 'returns empty hash' do
        expect(described_class.load_catalog).to eq({})
      end
    end

    context 'when config is valid' do
      before do
        allow(described_class).to receive(:safe_load_config).and_return({
          'schema_version' => '1.0',
          'app_identifier' => 'test_app',
          'entitlements' => { 'create_secrets' => {} },
          'plans' => { 'free_v1' => {} },
        })
      end

      it 'returns full catalog structure' do
        result = described_class.load_catalog
        expect(result['schema_version']).to eq('1.0')
        expect(result['app_identifier']).to eq('test_app')
        expect(result['entitlements']).to eq({ 'create_secrets' => {} })
        expect(result['plans']).to eq({ 'free_v1' => {} })
      end
    end
  end
end
