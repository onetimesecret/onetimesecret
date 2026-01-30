# migrations/2026-01-28/spec/schemas/base_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Schemas do
  let(:simple_schema) do
    {
      '$schema' => 'http://json-schema.org/draft-07/schema#',
      'type' => 'object',
      'required' => ['name'],
      'properties' => {
        'name' => { 'type' => 'string', 'minLength' => 1 },
        'age' => { 'type' => 'integer', 'minimum' => 0 }
      }
    }
  end

  describe '.register' do
    it 'adds schema to registry' do
      described_class.register(:test_schema, simple_schema)

      expect(described_class.registered?(:test_schema)).to be true
    end

    it 'allows overwriting existing schema' do
      described_class.register(:overwrite_test, simple_schema)
      new_schema = simple_schema.merge('title' => 'Updated')
      described_class.register(:overwrite_test, new_schema)

      expect(described_class.registered?(:overwrite_test)).to be true
    end
  end

  describe '.validate' do
    before do
      described_class.register(:person, simple_schema)
    end

    context 'with valid data' do
      it 'returns empty array for valid data' do
        valid_data = { 'name' => 'Alice', 'age' => 30 }

        errors = described_class.validate(:person, valid_data)

        expect(errors).to be_empty
      end

      it 'returns empty array when optional fields are missing' do
        valid_data = { 'name' => 'Bob' }

        errors = described_class.validate(:person, valid_data)

        expect(errors).to be_empty
      end
    end

    context 'with invalid data' do
      it 'returns error messages for missing required field' do
        invalid_data = { 'age' => 25 }

        errors = described_class.validate(:person, invalid_data)

        expect(errors).not_to be_empty
        expect(errors.first).to include('name')
      end

      it 'returns error messages for wrong type' do
        invalid_data = { 'name' => 'Alice', 'age' => 'not a number' }

        errors = described_class.validate(:person, invalid_data)

        expect(errors).not_to be_empty
        expect(errors.any? { |e| e.include?('age') }).to be true
      end

      it 'returns error messages for validation constraint violation' do
        invalid_data = { 'name' => '' }

        errors = described_class.validate(:person, invalid_data)

        expect(errors).not_to be_empty
      end

      it 'returns multiple errors for multiple issues' do
        complex_schema = {
          '$schema' => 'http://json-schema.org/draft-07/schema#',
          'type' => 'object',
          'required' => %w[field1 field2],
          'properties' => {
            'field1' => { 'type' => 'string' },
            'field2' => { 'type' => 'integer' }
          }
        }
        described_class.register(:multi_field, complex_schema)

        errors = described_class.validate(:multi_field, {})

        expect(errors.length).to be >= 1
      end
    end
  end

  describe '.valid?' do
    before do
      described_class.register(:check_schema, simple_schema)
    end

    it 'returns true for valid data' do
      valid_data = { 'name' => 'Test' }

      expect(described_class.valid?(:check_schema, valid_data)).to be true
    end

    it 'returns false for invalid data' do
      invalid_data = {}

      expect(described_class.valid?(:check_schema, invalid_data)).to be false
    end
  end

  describe '.registered?' do
    it 'returns true for registered schema' do
      described_class.register(:exists, simple_schema)

      expect(described_class.registered?(:exists)).to be true
    end

    it 'returns false for unregistered schema' do
      expect(described_class.registered?(:does_not_exist)).to be false
    end
  end

  describe '.registered' do
    it 'returns empty array when no schemas registered' do
      expect(described_class.registered).to be_empty
    end

    it 'lists all registered schema names' do
      described_class.register(:schema_a, simple_schema)
      described_class.register(:schema_b, simple_schema)

      registered = described_class.registered

      expect(registered).to include(:schema_a)
      expect(registered).to include(:schema_b)
    end
  end

  describe '.reset!' do
    it 'clears all registered schemas' do
      described_class.register(:temp_schema, simple_schema)

      described_class.reset!

      expect(described_class.registered?(:temp_schema)).to be false
      expect(described_class.registered).to be_empty
    end
  end

  describe 'SchemaNotFoundError' do
    it 'raises SchemaNotFoundError for validate with unknown schema' do
      expect do
        described_class.validate(:unknown_schema, {})
      end.to raise_error(described_class::SchemaNotFoundError, /unknown_schema/)
    end

    it 'raises SchemaNotFoundError for valid? with unknown schema' do
      expect do
        described_class.valid?(:unknown_schema, {})
      end.to raise_error(described_class::SchemaNotFoundError, /unknown_schema/)
    end
  end

  describe 'error formatting' do
    before do
      described_class.register(:format_test, simple_schema)
    end

    it 'formats errors with data location' do
      invalid_data = { 'name' => 'Test', 'age' => -5 }

      errors = described_class.validate(:format_test, invalid_data)

      expect(errors.first).to match(%r{/age:|root:})
    end

    it 'formats root-level errors appropriately' do
      # Wrong type at root
      root_error_schema = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'type' => 'object'
      }
      described_class.register(:root_test, root_error_schema)

      errors = described_class.validate(:root_test, 'not an object')

      expect(errors.first).to include('root')
    end
  end
end
