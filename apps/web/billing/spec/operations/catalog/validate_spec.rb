# apps/web/billing/spec/operations/catalog/validate_spec.rb
#
# frozen_string_literal: true

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/validate'

RSpec.describe Billing::Operations::Catalog::Validate, :billing do
  let(:config_path) { File.join(Onetime::HOME, 'etc', 'config', 'billing.yaml') }
  let(:schema_path) { File.join(Onetime::HOME, 'generated', 'schemas', 'config', 'billing.schema.json') }
  let(:progress_messages) { [] }
  let(:progress_proc) { ->(msg) { progress_messages << msg } }

  describe '.call' do
    context 'when catalog and schema exist' do
      before do
        allow(Billing::Config).to receive(:config_path).and_return(config_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(config_path).and_return(true)
        allow(File).to receive(:exist?).with(schema_path).and_return(true)
      end

      context 'valid catalog' do
        let(:valid_catalog) do
          {
            'app_identifier' => 'test_app',
            'plans' => {
              'test_plan' => {
                'name' => 'Test Plan',
                'tier' => 'single_team',
                'prices' => [
                  { 'amount' => 1000, 'interval' => 'month' },
                  { 'amount' => 10000, 'interval' => 'year' }
                ]
              }
            }
          }
        end

        let(:valid_schema) do
          { 'type' => 'object', 'properties' => {} }
        end

        before do
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with(config_path).and_return(valid_catalog.to_yaml)
          allow(File).to receive(:read).with(schema_path).and_return(valid_schema.to_json)
          allow(Billing::Config).to receive(:load_entitlements).and_return({})
        end

        subject(:result) { described_class.call(progress: progress_proc) }

        it 'returns success' do
          expect(result.success).to be true
        end

        it 'reports valid' do
          expect(result.valid).to be true
        end

        it 'counts plans validated' do
          expect(result.plans_validated).to eq(1)
        end

        it 'has empty errors' do
          expect(result.errors).to be_empty
        end
      end

      context 'catalog with schema errors' do
        let(:invalid_catalog) do
          { 'plans' => { 'bad_plan' => 'not_a_hash' } }
        end

        let(:schema) do
          {
            'type' => 'object',
            'properties' => {
              'plans' => {
                'type' => 'object',
                'additionalProperties' => { 'type' => 'object' }
              }
            }
          }
        end

        before do
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with(config_path).and_return(invalid_catalog.to_yaml)
          allow(File).to receive(:read).with(schema_path).and_return(schema.to_json)
          allow(Billing::Config).to receive(:load_entitlements).and_return({})
        end

        subject(:result) { described_class.call }

        it 'returns success (operation completed)' do
          expect(result.success).to be true
        end

        it 'reports invalid' do
          expect(result.valid).to be false
        end

        it 'includes schema errors' do
          expect(result.errors).not_to be_empty
          expect(result.errors.first).to include('Schema validation')
        end
      end
    end

    context 'missing catalog file' do
      before do
        allow(Billing::Config).to receive(:config_path).and_return('/nonexistent/billing.yaml')
        allow(File).to receive(:exist?).with('/nonexistent/billing.yaml').and_return(false)
      end

      subject(:result) { described_class.call }

      it 'returns failure' do
        expect(result.success).to be false
      end

      it 'includes file not found error' do
        expect(result.errors.first).to include('Catalog file not found')
      end
    end

    context 'missing schema file' do
      before do
        allow(Billing::Config).to receive(:config_path).and_return(config_path)
        allow(File).to receive(:exist?).with(config_path).and_return(true)
        allow(File).to receive(:exist?).with(schema_path).and_return(false)
      end

      subject(:result) { described_class.call }

      it 'returns failure' do
        expect(result.success).to be false
      end

      it 'includes schema not found error' do
        expect(result.errors.first).to include('Schema file not found')
      end
    end

    context 'strict mode' do
      let(:catalog_with_warnings) do
        {
          'plans' => {
            'paid_plan' => {
              'name' => 'Paid Plan',
              'tier' => 'single_team',
              'prices' => [{ 'amount' => 1000, 'interval' => 'month' }]
            }
          }
        }
      end

      let(:schema) { { 'type' => 'object' } }

      before do
        allow(Billing::Config).to receive(:config_path).and_return(config_path)
        allow(File).to receive(:exist?).with(config_path).and_return(true)
        allow(File).to receive(:exist?).with(schema_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(config_path).and_return(catalog_with_warnings.to_yaml)
        allow(File).to receive(:read).with(schema_path).and_return(schema.to_json)
        allow(Billing::Config).to receive(:load_entitlements).and_return({})
      end

      it 'fails on warnings in strict mode' do
        result = described_class.call(strict: true)
        expect(result.valid).to be false
        expect(result.warnings).not_to be_empty
      end

      it 'passes with warnings in non-strict mode' do
        result = described_class.call(strict: false)
        expect(result.valid).to be true
        expect(result.warnings).not_to be_empty
      end
    end
  end

  describe 'Result struct' do
    it 'has expected fields' do
      result = described_class::Result.new(success: true)
      expect(result).to respond_to(:success, :valid, :plans_validated,
                                   :errors, :warnings, :plan_summary)
    end

    it 'has sensible defaults' do
      result = described_class::Result.new(success: true)
      expect(result.errors).to eq([])
      expect(result.warnings).to eq([])
      expect(result.plan_summary).to eq({})
    end
  end
end
