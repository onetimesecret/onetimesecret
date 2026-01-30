# migrations/2026-01-28/spec/transforms/schema_validator_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::SchemaValidator do
  let(:stats) { {} }

  # Register test schemas before each example
  before do
    Migration::Schemas.register(:test_schema, {
      'type' => 'object',
      'required' => ['name'],
      'properties' => {
        'name' => { 'type' => 'string', 'minLength' => 1 },
        'count' => { 'type' => 'integer' }
      }
    })

    Migration::Schemas.register(:strict_schema, {
      'type' => 'object',
      'required' => ['id', 'type'],
      'properties' => {
        'id' => { 'type' => 'string' },
        'type' => { 'type' => 'string', 'enum' => ['a', 'b'] }
      }
    })
  end

  describe '#initialize' do
    it 'accepts schema name and field options' do
      validator = described_class.new(schema: :test_schema, field: :data, stats: stats)

      expect(validator.schema_name).to eq(:test_schema)
      expect(validator.field).to eq(:data)
      expect(validator.strict).to be(false)
    end

    it 'defaults field to :fields' do
      validator = described_class.new(schema: :test_schema, stats: stats)

      expect(validator.field).to eq(:fields)
    end

    it 'defaults strict to false' do
      validator = described_class.new(schema: :test_schema, stats: stats)

      expect(validator.strict).to be(false)
    end

    it 'raises ArgumentError for unregistered schema name' do
      expect { described_class.new(schema: :nonexistent_schema, stats: stats) }
        .to raise_error(ArgumentError, /Schema not registered: nonexistent_schema/)
    end
  end

  describe '#process' do
    context 'with valid data' do
      it 'passes record through unchanged without :validation_errors key' do
        validator = described_class.new(schema: :test_schema, stats: stats)
        record = { key: 'test:1', fields: { 'name' => 'Alice' } }

        result = validator.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:validation_errors)
      end

      it 'increments :validated stat' do
        validator = described_class.new(schema: :test_schema, stats: stats)
        record = { key: 'test:1', fields: { 'name' => 'Alice' } }

        validator.process(record)

        expect(stats[:validated]).to eq(1)
      end
    end

    context 'with invalid data in non-strict mode' do
      it 'returns record with :validation_errors array' do
        validator = described_class.new(schema: :test_schema, strict: false, stats: stats)
        record = { key: 'test:1', fields: { 'count' => 'not-an-integer' } }

        result = validator.process(record)

        expect(result).to be_a(Hash)
        expect(result[:validation_errors]).to be_an(Array)
        expect(result[:validation_errors]).not_to be_empty
      end

      it 'includes schema name in error messages' do
        validator = described_class.new(schema: :test_schema, strict: false, stats: stats)
        record = { key: 'test:1', fields: {} }

        result = validator.process(record)

        expect(result[:validation_errors].first).to include('[test_schema]')
      end

      it 'increments :validation_failures stat' do
        validator = described_class.new(schema: :test_schema, strict: false, stats: stats)
        record = { key: 'test:1', fields: {} }

        validator.process(record)

        expect(stats[:validation_failures]).to eq(1)
      end
    end

    context 'with invalid data in strict mode' do
      it 'returns nil to filter the record' do
        validator = described_class.new(schema: :strict_schema, strict: true, stats: stats)
        record = { key: 'test:1', fields: { 'id' => '123', 'type' => 'invalid' } }

        result = validator.process(record)

        expect(result).to be_nil
      end

      it 'increments :validation_failures stat' do
        validator = described_class.new(schema: :strict_schema, strict: true, stats: stats)
        record = { key: 'test:1', fields: {} }

        validator.process(record)

        expect(stats[:validation_failures]).to eq(1)
      end

      it 'increments :filtered_invalid stat' do
        validator = described_class.new(schema: :strict_schema, strict: true, stats: stats)
        record = { key: 'test:1', fields: {} }

        validator.process(record)

        expect(stats[:filtered_invalid]).to eq(1)
      end

      it 'outputs warning message' do
        validator = described_class.new(schema: :strict_schema, strict: true, stats: stats)
        record = { key: 'test:1', fields: {} }

        expect { validator.process(record) }
          .to output(/SchemaValidator: Filtered invalid record test:1/).to_stderr
      end
    end

    context 'with missing field' do
      it 'passes record through when :fields is nil' do
        validator = described_class.new(schema: :test_schema, stats: stats)
        record = { key: 'test:1', fields: nil }

        result = validator.process(record)

        expect(result).to eq(record)
      end

      it 'passes record through when field key is absent' do
        validator = described_class.new(schema: :test_schema, field: :data, stats: stats)
        record = { key: 'test:1' }

        result = validator.process(record)

        expect(result).to eq(record)
      end

      it 'increments :validation_skipped stat' do
        validator = described_class.new(schema: :test_schema, stats: stats)
        record = { key: 'test:1', fields: nil }

        validator.process(record)

        expect(stats[:validation_skipped]).to eq(1)
      end
    end

    context 'with custom field key' do
      it 'validates the specified field' do
        validator = described_class.new(schema: :test_schema, field: :v2_fields, stats: stats)
        record = {
          key: 'test:1',
          fields: { 'invalid' => 'data' },
          v2_fields: { 'name' => 'Valid' }
        }

        result = validator.process(record)

        expect(result).not_to have_key(:validation_errors)
        expect(stats[:validated]).to eq(1)
      end
    end

    context 'accumulating errors' do
      it 'appends to existing validation_errors' do
        validator = described_class.new(schema: :test_schema, strict: false, stats: stats)
        record = {
          key: 'test:1',
          fields: {},
          validation_errors: ['Previous error']
        }

        result = validator.process(record)

        expect(result[:validation_errors].first).to eq('Previous error')
        expect(result[:validation_errors].length).to be > 1
      end
    end

    context 'additionalProperties behavior' do
      before do
        Migration::Schemas.register(:strict_no_additional, {
          'type' => 'object',
          'required' => ['id'],
          'properties' => {
            'id' => { 'type' => 'string' }
          },
          'additionalProperties' => false
        })

        Migration::Schemas.register(:allow_additional, {
          'type' => 'object',
          'required' => ['id'],
          'properties' => {
            'id' => { 'type' => 'string' }
          },
          'additionalProperties' => true
        })
      end

      it 'rejects unknown properties when additionalProperties is false' do
        validator = described_class.new(schema: :strict_no_additional, stats: stats)
        record = { key: 'test:1', fields: { 'id' => '123', 'unknown_field' => 'value' } }

        result = validator.process(record)

        expect(result[:validation_errors]).to be_an(Array)
        expect(result[:validation_errors]).not_to be_empty
        expect(stats[:validation_failures]).to eq(1)
      end

      it 'allows unknown properties when additionalProperties is true' do
        validator = described_class.new(schema: :allow_additional, stats: stats)
        record = { key: 'test:1', fields: { 'id' => '123', 'extra' => 'allowed' } }

        result = validator.process(record)

        expect(result).not_to have_key(:validation_errors)
        expect(stats[:validated]).to eq(1)
      end
    end

    context 'with nested schema validation' do
      before do
        Migration::Schemas.register(:nested_schema, {
          'type' => 'object',
          'required' => ['user'],
          'properties' => {
            'user' => {
              'type' => 'object',
              'required' => ['email'],
              'properties' => {
                'email' => { 'type' => 'string', 'format' => 'email' },
                'settings' => {
                  'type' => 'object',
                  'properties' => {
                    'theme' => { 'type' => 'string', 'enum' => ['light', 'dark'] }
                  }
                }
              }
            }
          }
        })
      end

      it 'validates nested object structure' do
        validator = described_class.new(schema: :nested_schema, stats: stats)
        record = {
          key: 'test:1',
          fields: {
            'user' => {
              'email' => 'test@example.com',
              'settings' => { 'theme' => 'light' }
            }
          }
        }

        result = validator.process(record)

        expect(result).not_to have_key(:validation_errors)
        expect(stats[:validated]).to eq(1)
      end

      it 'reports errors at nested path locations' do
        validator = described_class.new(schema: :nested_schema, stats: stats)
        record = {
          key: 'test:1',
          fields: {
            'user' => {
              'email' => 'test@example.com',
              'settings' => { 'theme' => 'invalid_theme' }
            }
          }
        }

        result = validator.process(record)

        expect(result[:validation_errors]).to be_an(Array)
        # Error should reference the nested path
        expect(result[:validation_errors].first).to match(/theme|settings/)
      end
    end

    context 'with many validation errors' do
      before do
        # Use multiple type violations instead of missing required fields
        # json_schemer reports missing required fields as a single error
        Migration::Schemas.register(:multi_error, {
          'type' => 'object',
          'properties' => {
            'field1' => { 'type' => 'string' },
            'field2' => { 'type' => 'integer' },
            'field3' => { 'type' => 'boolean' },
            'field4' => { 'type' => 'array' },
            'field5' => { 'type' => 'object' }
          }
        })
      end

      it 'collects all validation errors not just the first' do
        validator = described_class.new(schema: :multi_error, strict: false, stats: stats)
        # All fields have wrong types
        record = {
          key: 'test:1',
          fields: {
            'field1' => 123,       # should be string
            'field2' => 'string',  # should be integer
            'field3' => 'yes',     # should be boolean
            'field4' => 'array',   # should be array
            'field5' => 'object'   # should be object
          }
        }

        result = validator.process(record)

        # Should have 5 type errors, one per field
        expect(result[:validation_errors].length).to eq(5)
      end

      it 'reports missing required fields in a single error message' do
        Migration::Schemas.register(:multi_required, {
          'type' => 'object',
          'required' => %w[a b c d e],
          'properties' => {}
        })

        validator = described_class.new(schema: :multi_required, strict: false, stats: stats)
        record = { key: 'test:1', fields: {} }

        result = validator.process(record)

        # json_schemer reports all missing required fields in one error
        expect(result[:validation_errors].length).to eq(1)
        expect(result[:validation_errors].first).to include('missing required properties')
      end
    end

    context 'with multiple field keys present' do
      it 'only validates the specified field key' do
        validator = described_class.new(schema: :test_schema, field: :v2_fields, stats: stats)
        record = {
          key: 'test:1',
          fields: {},  # Invalid against schema (missing name)
          v2_fields: { 'name' => 'Valid' }  # Valid
        }

        result = validator.process(record)

        # Should validate v2_fields, not fields
        expect(result).not_to have_key(:validation_errors)
        expect(stats[:validated]).to eq(1)
      end

      it 'validates correct field even when others are invalid' do
        validator = described_class.new(schema: :test_schema, field: :fields, stats: stats)
        record = {
          key: 'test:1',
          fields: {},  # Invalid
          v2_fields: { 'name' => 'Valid' }  # Valid but not checked
        }

        result = validator.process(record)

        expect(result[:validation_errors]).not_to be_empty
        expect(stats[:validation_failures]).to eq(1)
      end
    end

    context 'chained validators' do
      before do
        Migration::Schemas.register(:v1_schema, {
          'type' => 'object',
          'required' => ['email'],
          'properties' => {
            'email' => { 'type' => 'string', 'format' => 'email' }
          }
        })

        Migration::Schemas.register(:v2_schema, {
          'type' => 'object',
          'required' => ['objid'],
          'properties' => {
            'objid' => { 'type' => 'string', 'pattern' => '^[0-9a-f-]+$' }
          }
        })
      end

      it 'accumulates errors from multiple validators' do
        stats1 = {}
        stats2 = {}
        v1_validator = described_class.new(schema: :v1_schema, field: :fields, stats: stats1)
        v2_validator = described_class.new(schema: :v2_schema, field: :v2_fields, stats: stats2)

        record = {
          key: 'test:1',
          fields: {},           # Missing email - invalid
          v2_fields: {}         # Missing objid - invalid
        }

        # Simulate pipeline: record passes through both validators
        result = v1_validator.process(record)
        result = v2_validator.process(result)

        # Both validators should have added errors
        expect(result[:validation_errors].size).to eq(2)
        expect(result[:validation_errors].any? { |e| e.include?('[v1_schema]') }).to be true
        expect(result[:validation_errors].any? { |e| e.include?('[v2_schema]') }).to be true

        expect(stats1[:validation_failures]).to eq(1)
        expect(stats2[:validation_failures]).to eq(1)
      end

      it 'maintains valid count when second validator passes' do
        stats1 = {}
        stats2 = {}
        v1_validator = described_class.new(schema: :v1_schema, field: :fields, stats: stats1)
        v2_validator = described_class.new(schema: :v2_schema, field: :v2_fields, stats: stats2)

        record = {
          key: 'test:1',
          fields: {},                    # Invalid
          v2_fields: { 'objid' => 'abc-123' }  # Valid
        }

        result = v1_validator.process(record)
        result = v2_validator.process(result)

        # First failed, second passed
        expect(stats1[:validation_failures]).to eq(1)
        expect(stats2[:validated]).to eq(1)

        # Only first validator's error should be present
        expect(result[:validation_errors].size).to eq(1)
        expect(result[:validation_errors].first).to include('[v1_schema]')
      end

      it 'strict mode filters on first invalid validator' do
        stats1 = {}
        v1_validator = described_class.new(schema: :v1_schema, field: :fields, strict: true, stats: stats1)

        record = {
          key: 'test:1',
          fields: {},                    # Invalid - will be filtered
          v2_fields: { 'objid' => 'abc-123' }
        }

        result = v1_validator.process(record)

        # First validator returns nil (filtered)
        expect(result).to be_nil
        expect(stats1[:filtered_invalid]).to eq(1)

        # Second validator never sees record (would be called with nil in real pipeline)
        # This documents that strict filtering short-circuits the pipeline
      end
    end

    context 'empty object validation' do
      before do
        Migration::Schemas.register(:empty_allowed, {
          'type' => 'object',
          'properties' => {}
        })
      end

      it 'validates empty object when no required fields' do
        validator = described_class.new(schema: :empty_allowed, stats: stats)
        record = { key: 'test:1', fields: {} }

        result = validator.process(record)

        expect(result).not_to have_key(:validation_errors)
        expect(stats[:validated]).to eq(1)
      end
    end

    context 'with array type fields' do
      before do
        Migration::Schemas.register(:array_schema, {
          'type' => 'object',
          'properties' => {
            'tags' => {
              'type' => 'array',
              'items' => { 'type' => 'string' },
              'minItems' => 1
            }
          },
          'required' => ['tags']
        })
      end

      it 'validates array fields correctly' do
        validator = described_class.new(schema: :array_schema, stats: stats)
        record = { key: 'test:1', fields: { 'tags' => ['a', 'b', 'c'] } }

        result = validator.process(record)

        expect(result).not_to have_key(:validation_errors)
        expect(stats[:validated]).to eq(1)
      end

      it 'reports error for empty array when minItems required' do
        validator = described_class.new(schema: :array_schema, stats: stats)
        record = { key: 'test:1', fields: { 'tags' => [] } }

        result = validator.process(record)

        expect(result[:validation_errors]).not_to be_empty
        expect(stats[:validation_failures]).to eq(1)
      end

      it 'reports error for wrong item types in array' do
        validator = described_class.new(schema: :array_schema, stats: stats)
        record = { key: 'test:1', fields: { 'tags' => [1, 2, 3] } }

        result = validator.process(record)

        expect(result[:validation_errors]).not_to be_empty
        expect(stats[:validation_failures]).to eq(1)
      end
    end
  end
end
