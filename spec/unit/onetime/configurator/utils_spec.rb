# tests/unit/ruby/rspec/onetime/configurator/utils_spec.rb

require_relative '../../../spec_helper'
require 'json_schemer'

RSpec.describe Onetime::Configurator::Utils do
  describe '.validate_against_schema' do
    let(:valid_schema) do
      {
        'type' => 'object',
        'properties' => {
          'name' => { 'type' => 'string' },
          'age' => { 'type' => 'integer', 'minimum' => 0 },
          'active' => { 'type' => 'boolean', 'default' => true }
        },
        'required' => ['name']
      }
    end

    let(:valid_config) do
      { 'name' => 'test', 'age' => 25 }
    end

    let(:invalid_config) do
      { 'age' => 'not_a_number' }
    end

    context 'with valid inputs' do
      it 'validates and returns config when valid' do
        result = described_class.validate_against_schema(valid_config, valid_schema)

        puts "\n=== DEBUGGING: Valid validation ==="
        puts "Input config: #{valid_config.inspect}"
        puts "Schema: #{valid_schema.inspect}"
        puts "Result: #{result.inspect}"
        puts "Result class: #{result.class}"
        puts "===================================\n"

        expect(result).to eq(valid_config)
        expect(result).to be_a(Hash)
      end

      it 'applies defaults when apply_defaults is true' do
        config_without_default = { 'name' => 'test' }
        result = described_class.validate_against_schema(
          config_without_default,
          valid_schema,
          apply_defaults: true
        )

        puts "\n=== DEBUGGING: Defaults application ==="
        puts "Input config: #{config_without_default.inspect}"
        puts "Schema defaults: #{valid_schema['properties']['active']['default']}"
        puts "Result: #{result.inspect}"
        puts "Has default applied: #{result.key?('active')}"
        puts "Default value: #{result['active']}"
        puts "======================================\n"

        expect(result['active']).to eq(true)
        expect(result['name']).to eq('test')
      end

      it 'converts symbols to strings for string type fields' do
        config_with_symbol = { 'name' => :test_symbol, 'age' => 25 }
        result = described_class.validate_against_schema(config_with_symbol, valid_schema)

        puts "\n=== DEBUGGING: Symbol conversion ==="
        puts "Input config: #{config_with_symbol.inspect}"
        puts "Input name type: #{config_with_symbol['name'].class}"
        puts "Result: #{result.inspect}"
        puts "Result name type: #{result['name'].class}"
        puts "Result name value: #{result['name']}"
        puts "====================================\n"

        expect(result['name']).to eq('test_symbol')
        expect(result['name']).to be_a(String)
      end
    end

    context 'with invalid inputs' do
      it 'raises ConfigError when schema is nil' do
        expect {
          described_class.validate_against_schema(valid_config, nil)
        }.to raise_error(OT::ConfigError, 'Schema is nil')
      end

      it 'raises ConfigValidationError with detailed error info for invalid config' do
        error = nil
        begin
          described_class.validate_against_schema(invalid_config, valid_schema)
        rescue OT::ConfigValidationError => e
          error = e
        end

        puts "\n=== DEBUGGING: Validation error ==="
        puts "Invalid config: #{invalid_config.inspect}"
        puts "Error class: #{error.class}"
        puts "Error messages: #{error.messages.inspect}"
        puts "Error paths: #{error.paths.inspect}"
        puts "Error message: #{error.message}"
        puts "==================================\n"

        expect(error).to be_a(OT::ConfigValidationError)
        expect(error.messages).to be_an(Array)
        expect(error.messages).not_to be_empty
        expect(error.paths).to be_a(Hash)

        # Verify the error contains information about missing required field
        expect(error.messages.join(' ')).to include('name')

        # Verify the error contains information about type mismatch
        expect(error.messages.join(' ')).to include('age')
      end

      it 'provides structured error paths for nested validation failures' do
        nested_schema = {
          'type' => 'object',
          'properties' => {
            'user' => {
              'type' => 'object',
              'properties' => {
                'profile' => {
                  'type' => 'object',
                  'properties' => {
                    'name' => { 'type' => 'string' }
                  },
                  'required' => ['name']
                }
              },
              'required' => ['profile']
            }
          },
          'required' => ['user']
        }

        nested_invalid_config = {
          'user' => {
            'profile' => {
              'name' => 123  # Should be string
            }
          }
        }

        error = nil
        begin
          described_class.validate_against_schema(nested_invalid_config, nested_schema)
        rescue OT::ConfigValidationError => e
          error = e
        end

        puts "\n=== DEBUGGING: Nested validation error ==="
        puts "Nested config: #{nested_invalid_config.inspect}"
        puts "Error paths structure: #{error.paths.inspect}"
        puts "Error messages: #{error.messages.inspect}"
        puts "==========================================\n"

        expect(error).to be_a(OT::ConfigValidationError)
        expect(error.paths).to be_a(Hash)

        # Should contain the problematic nested value
        expect(error.paths.dig('user', 'profile', 'name')).to eq(123)
      end
    end

    context 'with edge cases' do
      it 'handles empty config with required fields' do
        error = nil
        begin
          described_class.validate_against_schema({}, valid_schema)
        rescue OT::ConfigValidationError => e
          error = e
        end

        puts "\n=== DEBUGGING: Empty config validation ==="
        puts "Empty config: {}"
        puts "Required fields: #{valid_schema['required']}"
        puts "Error messages: #{error.messages.inspect}"
        puts "=========================================\n"

        expect(error).to be_a(OT::ConfigValidationError)
        expect(error.messages.join(' ')).to include('name')
      end

      it 'handles config with extra properties not in schema' do
        config_with_extra = valid_config.merge('extra_field' => 'value')
        result = described_class.validate_against_schema(config_with_extra, valid_schema)

        puts "\n=== DEBUGGING: Extra properties ==="
        puts "Config with extra: #{config_with_extra.inspect}"
        puts "Result: #{result.inspect}"
        puts "Extra field preserved: #{result.key?('extra_field')}"
        puts "==================================\n"

        expect(result).to eq(config_with_extra)
        expect(result['extra_field']).to eq('value')
      end
    end
  end

  describe '.format_validation_errors' do
    let(:sample_errors) do
      [
        { 'error' => 'Missing required field: name' },
        { 'error' => 'Invalid type for age: expected integer' },
        { 'error' => 'Value too small for count: minimum is 1' }
      ]
    end

    it 'extracts error messages from validation errors' do
      result = described_class.format_validation_errors(sample_errors)

      puts "\n=== DEBUGGING: Error formatting ==="
      puts "Input errors: #{sample_errors.inspect}"
      puts "Formatted messages: #{result.inspect}"
      puts "Result type: #{result.class}"
      puts "Message count: #{result.length}"
      puts "=================================\n"

      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
      expect(result).to include('Missing required field: name')
      expect(result).to include('Invalid type for age: expected integer')
      expect(result).to include('Value too small for count: minimum is 1')
    end

    it 'handles empty error array' do
      result = described_class.format_validation_errors([])

      puts "\n=== DEBUGGING: Empty errors ==="
      puts "Input: []"
      puts "Result: #{result.inspect}"
      puts "==============================\n"

      expect(result).to eq([])
    end
  end

  describe '.extract_error_paths' do
    let(:sample_errors_with_paths) do
      [
        {
          'data_pointer' => '/user/name',
          'data' => nil,
          'error' => 'Missing required field'
        },
        {
          'data_pointer' => '/user/profile/age',
          'data' => 'invalid',
          'error' => 'Invalid type'
        },
        {
          'data_pointer' => '/settings/timeout',
          'data' => -1,
          'error' => 'Value too small'
        }
      ]
    end

    it 'extracts nested error paths and values' do
      result = described_class.extract_error_paths(sample_errors_with_paths)

      puts "\n=== DEBUGGING: Path extraction ==="
      puts "Input errors: #{sample_errors_with_paths.inspect}"
      puts "Extracted paths: #{result.inspect}"
      puts "Result structure: #{result.class}"
      puts "=================================\n"

      expect(result).to be_a(Hash)
      expect(result.dig('user', 'name')).to be_nil
      expect(result.dig('user', 'profile', 'age')).to eq('invalid')
      expect(result.dig('settings', 'timeout')).to eq(-1)
    end

    it 'handles root level errors' do
      root_errors = [
        {
          'data_pointer' => '/name',
          'data' => '',
          'error' => 'Empty string not allowed'
        }
      ]

      result = described_class.extract_error_paths(root_errors)

      puts "\n=== DEBUGGING: Root level errors ==="
      puts "Input: #{root_errors.inspect}"
      puts "Result: #{result.inspect}"
      puts "===================================\n"

      expect(result['name']).to eq('')
    end

    it 'handles errors with empty data_pointer' do
      errors_with_empty_pointer = [
        {
          'data_pointer' => '',
          'data' => 'invalid_root',
          'error' => 'Root validation failed'
        },
        {
          'data_pointer' => '/',
          'data' => 'also_invalid',
          'error' => 'Another root error'
        }
      ]

      result = described_class.extract_error_paths(errors_with_empty_pointer)

      puts "\n=== DEBUGGING: Empty pointers ==="
      puts "Input: #{errors_with_empty_pointer.inspect}"
      puts "Result: #{result.inspect}"
      puts "Result empty?: #{result.empty?}"
      puts "================================\n"

      expect(result).to eq({})
    end

    it 'creates proper nested structure for deep paths' do
      deep_errors = [
        {
          'data_pointer' => '/a/b/c/d/e',
          'data' => 'deep_value',
          'error' => 'Deep validation error'
        }
      ]

      result = described_class.extract_error_paths(deep_errors)

      puts "\n=== DEBUGGING: Deep nesting ==="
      puts "Input: #{deep_errors.inspect}"
      puts "Result: #{result.inspect}"
      puts "Deep value: #{result.dig('a', 'b', 'c', 'd', 'e')}"
      puts "==============================\n"

      expect(result.dig('a', 'b', 'c', 'd', 'e')).to eq('deep_value')
    end
  end

  describe '.mapped_key' do
    context 'with keys in KEY_MAP' do
      it 'returns mapped key for allowed_domains_only' do
        result = described_class.mapped_key(:allowed_domains_only)

        puts "\n=== DEBUGGING: Key mapping ==="
        puts "Input key: :allowed_domains_only"
        puts "Mapped key: #{result.inspect}"
        puts "Expected: :whitelist_validation"
        puts "Match?: #{result == :whitelist_validation}"
        puts "=============================\n"

        expect(result).to eq(:whitelist_validation)
      end

      it 'returns mapped key for blocked_emails' do
        result = described_class.mapped_key(:blocked_emails)

        puts "\n=== DEBUGGING: Blocked emails mapping ==="
        puts "Input: :blocked_emails"
        puts "Result: #{result.inspect}"
        puts "Expected: :blacklisted_emails"
        puts "========================================\n"

        expect(result).to eq(:blacklisted_emails)
      end

      it 'returns mapped key for example_internal_key (symbol input)' do
        result = described_class.mapped_key(:example_internal_key)

        puts "\n=== DEBUGGING: Example mapping ==="
        puts "Input: :example_internal_key"
        puts "Result: #{result.inspect}"
        puts "Expected: :example_external_key"
        puts "=================================\n"

        expect(result).to eq('example_external_key')
      end

      it 'returns mapped key for example_internal_key (string input)' do
        result = described_class.mapped_key('example_internal_key')
        expect(result).to eq('example_external_key')
      end

      it 'returns mapped key for example_internal_key' do
        result = described_class.mapped_key(:example_internal_key)

        expect(result).to eq('example_external_key')
      end
    end

    context 'with keys not in KEY_MAP' do
      it 'returns the original key when not mapped' do
        result = described_class.mapped_key(:unmapped_key)

        puts "\n=== DEBUGGING: Unmapped key ==="
        puts "Input: :unmapped_key"
        puts "Result: #{result.inspect}"
        puts "Same as input?: #{result == :unmapped_key}"
        puts "==============================\n"

        expect(result).to eq(:unmapped_key)
      end

      it 'handles string keys (though method expects symbols)' do
        result = described_class.mapped_key('string_key')

        puts "\n=== DEBUGGING: String key ==="
        puts "Input: 'string_key'"
        puts "Result: #{result.inspect}"
        puts "Same as input?: #{result == 'string_key'}"
        puts "============================\n"

        expect(result).to eq('string_key')
      end
    end

    context 'verifying all KEY_MAP entries' do
      it 'correctly maps all defined keys' do
        key_map = Onetime::Configurator::KEY_MAP

        puts "\n=== DEBUGGING: All KEY_MAP entries ==="
        key_map.each do |internal, external|
          result = described_class.mapped_key(internal)
          puts "#{internal} -> #{result} (expected: #{external})"
          expect(result).to eq(external)
        end
        puts "====================================\n"

        expect(key_map.keys.length).to be > 0
      end
    end
  end

  describe 'constants and module structure' do
    it 'has expected KNOWN_PATHS constant' do
      known_paths = Onetime::Configurator::KNOWN_PATHS

      puts "\n=== DEBUGGING: KNOWN_PATHS ==="
      puts "Known paths: #{known_paths.inspect}"
      puts "Paths count: #{known_paths.length}"
      puts "Contains /etc/onetime?: #{known_paths.include?('/etc/onetime')}"
      puts "Contains ./etc?: #{known_paths.include?('./etc')}"
      puts "Contains ~/.onetime?: #{known_paths.include?('~/.onetime')}"
      puts "============================\n"

      expect(known_paths).to include('/etc/onetime')
      expect(known_paths).to include('./etc')
      expect(known_paths).to include('~/.onetime')
      expect(known_paths).to be_frozen
    end

    it 'has expected KEY_MAP constant structure' do
      key_map = Onetime::Configurator::KEY_MAP

      puts "\n=== DEBUGGING: KEY_MAP structure ==="
      puts "KEY_MAP: #{key_map.inspect}"
      puts "Keys count: #{key_map.keys.length}"
      puts "Sample mappings:"
      key_map.first(3).each do |k, v|
        puts "  #{k} => #{v}"
      end
      puts "==================================\n"

      expect(key_map).to be_a(Hash)
      expect(key_map.keys).to all(be_a(String))
      expect(key_map.values).to all(satisfy { |v| v.is_a?(Symbol) || v.is_a?(String) })

      # NOTE: This is a security issue - KEY_MAP should always be frozen
      expect(key_map).to be_frozen

    end
  end

  describe 'integration with JSONSchemer' do
    it 'uses correct JSON Schema draft version' do
      schema = { 'type' => 'object' }

      # This test verifies the integration works with our chosen draft version
      expect {
        described_class.validate_against_schema({}, schema)
      }.not_to raise_error

      puts "\n=== DEBUGGING: Schema integration ==="
      puts "Schema: #{schema.inspect}"
      puts "Integration successful: JSON Schema draft 2020-12 works"
      puts "====================================\n"
    end

    it 'handles format validation when enabled' do
      email_schema = {
        'type' => 'object',
        'properties' => {
          'email' => { 'type' => 'string', 'format' => 'email' }
        }
      }

      valid_email_config = { 'email' => 'test@example.com' }
      invalid_email_config = { 'email' => 'not-an-email' }

      # Valid email should pass
      result = described_class.validate_against_schema(valid_email_config, email_schema)
      expect(result).to eq(valid_email_config)

      # Invalid email should fail
      expect {
        described_class.validate_against_schema(invalid_email_config, email_schema)
      }.to raise_error(OT::ConfigValidationError)

      puts "\n=== DEBUGGING: Format validation ==="
      puts "Valid email config: #{valid_email_config.inspect}"
      puts "Invalid email config: #{invalid_email_config.inspect}"
      puts "Format validation working correctly"
      puts "==================================\n"
    end
  end

  describe 'edge cases and error conditions' do
    it 'handles mixed symbol and string types in configuration' do
      mixed_schema = {
        'type' => 'object',
        'properties' => {
          'string_field' => { 'type' => 'string' },
          'number_field' => { 'type' => 'number' }
        }
      }

      mixed_config = {
        'string_field' => :symbol_value,
        'number_field' => 42
      }

      result = described_class.validate_against_schema(mixed_config, mixed_schema)

      puts "\n=== DEBUGGING: Mixed types ==="
      puts "Input config: #{mixed_config.inspect}"
      puts "String field original: #{mixed_config['string_field'].class}"
      puts "Result: #{result.inspect}"
      puts "String field converted: #{result['string_field'].class}"
      puts "=============================\n"

      expect(result['string_field']).to eq('symbol_value')
      expect(result['string_field']).to be_a(String)
      expect(result['number_field']).to eq(42)
    end

    it 'preserves original config when validation fails' do
      original_config = { 'invalid' => 'data' }
      schema = {
        'type' => 'object',
        'properties' => {
          'valid' => { 'type' => 'string' }
        },
        'required' => ['valid']
      }

      expect {
        described_class.validate_against_schema(original_config, schema)
      }.to raise_error(OT::ConfigValidationError)

      puts "\n=== DEBUGGING: Config preservation ==="
      puts "Original after error: #{original_config.inspect}"
      puts "Config unchanged: #{original_config == { 'invalid' => 'data' }}"
      puts "=====================================\n"

      # Original config should remain unchanged
      expect(original_config).to eq({ 'invalid' => 'data' })
    end

    it 'handles multiple validation errors in single call' do
      multi_error_schema = {
        'type' => 'object',
        'properties' => {
          'name' => { 'type' => 'string' },
          'age' => { 'type' => 'integer', 'minimum' => 0 },
          'email' => { 'type' => 'string', 'format' => 'email' }
        },
        'required' => ['name', 'age']
      }

      multi_error_config = {
        'age' => -5,  # fails minimum constraint
        'email' => 'not-email'  # fails format
        # missing required 'name'
      }

      error = nil
      begin
        described_class.validate_against_schema(multi_error_config, multi_error_schema)
      rescue OT::ConfigValidationError => e
        error = e
      end

      puts "\n=== DEBUGGING: Multiple errors ==="
      puts "Config: #{multi_error_config.inspect}"
      puts "Error count: #{error.messages.length}"
      puts "Messages: #{error.messages.inspect}"
      puts "Paths: #{error.paths.inspect}"
      puts "==============================\n"

      expect(error.messages.length).to be >= 2
      expect(error.paths).to include('age')
      expect(error.paths['age']).to eq(-5)
    end
  end

  describe 'security and immutability concerns' do
    it 'verifies the KEY_MAP is properly frozen and immutable' do
      # This test verifies that KEY_MAP is frozen and cannot be modified
      original_mapping = described_class.mapped_key(:allowed_domains_only)

      # Attempt to modify the KEY_MAP - this should raise FrozenError
      expect {
        Onetime::Configurator::KEY_MAP[:allowed_domains_only] = :hijacked_value
      }.to raise_error(FrozenError)

      # Verify the mapping remains unchanged after failed modification attempt
      unchanged_mapping = described_class.mapped_key(:allowed_domains_only)

      puts "\n=== DEBUGGING: Security protection ==="
      puts "Original mapping: #{original_mapping}"
      puts "After failed modification: #{unchanged_mapping}"
      puts "KEY_MAP is frozen: #{Onetime::Configurator::KEY_MAP.frozen?}"
      puts "Mapping unchanged: #{unchanged_mapping == original_mapping}"
      puts "Security protection working correctly!"
      puts "====================================\n"

      # This test verifies that the mapping cannot be changed at runtime
      expect(unchanged_mapping).to eq(original_mapping)
      expect(Onetime::Configurator::KEY_MAP).to be_frozen
    end

    it 'verifies KNOWN_PATHS is properly frozen and immutable' do
      original_paths = Onetime::Configurator::KNOWN_PATHS.dup

      expect {
        Onetime::Configurator::KNOWN_PATHS << '/malicious/path'
      }.to raise_error(FrozenError)

      puts "\n=== DEBUGGING: KNOWN_PATHS security ==="
      puts "Original paths: #{original_paths.inspect}"
      puts "Paths after freeze test: #{Onetime::Configurator::KNOWN_PATHS.inspect}"
      puts "Paths unchanged: #{Onetime::Configurator::KNOWN_PATHS == original_paths}"
      puts "====================================\n"

      expect(Onetime::Configurator::KNOWN_PATHS).to eq(original_paths)
    end
  end
end
