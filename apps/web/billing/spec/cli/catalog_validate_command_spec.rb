# apps/web/billing/spec/cli/catalog_validate_command_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing catalog validate` CLI wrapper.
#
# These test the CLI's public interface and delegation to operations.
# For detailed logic tests, see: spec/operations/catalog/validate_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_validate_command'

RSpec.describe 'Billing Catalog Validate CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingCatalogValidateCommand.new }

  def run_command(**kwargs)
    old_stdout = $stdout
    $stdout    = StringIO.new
    status     = nil
    begin
      command.call(**kwargs)
    rescue SystemExit => e
      status = e.status
    end
    [$stdout.string, status]
  ensure
    $stdout = old_stdout
  end

  before do
    allow(command).to receive(:boot_application!)
  end

  describe 'generated schema' do
    it 'is committed at the path the command loads' do
      schema_path = File.join(Onetime::HOME, 'generated', 'schemas', 'config', 'billing.schema.json')
      expect(File.exist?(schema_path)).to be(true),
        "Expected generated schema at #{schema_path}. Run: pnpm run schemas:json:generate"
    end
  end

  describe '#call' do
    context 'when validation succeeds with no warnings' do
      let(:valid_result) do
        Billing::Operations::Catalog::Validate::Result.new(
          success: true,
          valid: true,
          plans_validated: 3,
          plan_summary: { valid: [{ id: 'test_v1', name: 'Test', tier: 'free' }], invalid: [], has_free_tier: true },
        )
      end

      before do
        allow(Billing::Operations::Catalog::Validate).to receive(:call).and_return(valid_result)
      end

      it 'reports VALIDATION PASSED' do
        output, status = run_command
        expect(output).to include('VALIDATION PASSED')
        expect(status).to eq(0)
      end

      it 'shows plan summary' do
        output, _status = run_command
        expect(output).to include('VALID (1)')
        expect(output).to include('Test')
      end
    end

    context 'when validation succeeds with warnings (non-strict)' do
      let(:warnings_result) do
        Billing::Operations::Catalog::Validate::Result.new(
          success: true,
          valid: true,
          plans_validated: 2,
          warnings: ['Plan test_v1: Missing yearly pricing'],
          plan_summary: { valid: [], invalid: [], has_free_tier: false },
        )
      end

      before do
        allow(Billing::Operations::Catalog::Validate).to receive(:call).and_return(warnings_result)
      end

      it 'passes with warnings' do
        output, status = run_command
        expect(output).to include('VALIDATION PASSED (warnings only)')
        expect(output).to include('1 warning(s)')
        expect(status).to eq(0)
      end
    end

    context 'when validation succeeds with warnings (strict mode)' do
      let(:warnings_result) do
        Billing::Operations::Catalog::Validate::Result.new(
          success: true,
          valid: false,  # strict mode makes warnings fail
          plans_validated: 2,
          warnings: ['Plan test_v1: Missing yearly pricing'],
          plan_summary: { valid: [], invalid: [], has_free_tier: false },
        )
      end

      before do
        allow(Billing::Operations::Catalog::Validate).to receive(:call).and_return(warnings_result)
      end

      it 'passes strict: true to operation' do
        expect(Billing::Operations::Catalog::Validate).to receive(:call) do |args|
          expect(args[:strict]).to be(true)
          warnings_result
        end

        run_command(strict: true)
      end

      it 'fails in strict mode with warnings' do
        output, status = run_command(strict: true)
        expect(output).to include('VALIDATION FAILED')
        expect(output).to include('warning(s) in strict mode')
        expect(status).to eq(1)
      end
    end

    context 'when validation fails with errors' do
      let(:error_result) do
        Billing::Operations::Catalog::Validate::Result.new(
          success: true,
          valid: false,
          plans_validated: 1,
          errors: ['Schema validation: /plans/bad_plan: required property name is missing'],
          plan_summary: { valid: [], invalid: [{ id: 'bad_plan', name: nil, tier: nil }], has_free_tier: false },
        )
      end

      before do
        allow(Billing::Operations::Catalog::Validate).to receive(:call).and_return(error_result)
      end

      it 'reports VALIDATION FAILED' do
        output, status = run_command
        expect(output).to include('VALIDATION FAILED')
        expect(output).to include('1 error(s) found')
        expect(status).to eq(1)
      end

      it 'shows error details' do
        output, _status = run_command
        expect(output).to include('Schema validation:')
      end
    end

    context 'when operation itself fails' do
      let(:failure_result) do
        Billing::Operations::Catalog::Validate::Result.new(
          success: false,
          errors: ['Catalog file not found: /path/to/billing.yaml'],
        )
      end

      before do
        allow(Billing::Operations::Catalog::Validate).to receive(:call).and_return(failure_result)
      end

      it 'displays error and exits 1' do
        output, status = run_command
        expect(output).to include('Error: Catalog file not found')
        expect(status).to eq(1)
      end
    end
  end
end
