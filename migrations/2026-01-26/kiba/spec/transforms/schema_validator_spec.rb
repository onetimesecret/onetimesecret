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
  end
end
