# apps/web/billing/spec/cli/catalog_push_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing catalog push` CLI wrapper.
#
# These test the CLI's public interface and delegation to operations.
# For detailed logic tests (analyze_changes, detect_product_updates, etc.),
# see: spec/operations/catalog/push_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_push_command'

RSpec.describe 'Billing Catalog Push CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingCatalogPushCommand.new }

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    begin
      yield
    rescue SystemExit
      # Ignore exit calls
    end
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  before do
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:stripe_configured?).and_return(true)
  end

  describe '#call' do
    context 'when Stripe is not configured' do
      before do
        allow(command).to receive(:stripe_configured?).and_return(false)
      end

      it 'exits early without pushing' do
        expect(Billing::Operations::Catalog::Push).not_to receive(:call)
        command.call
      end
    end

    context 'when no changes needed' do
      let(:no_changes_result) do
        Billing::Operations::Catalog::Push::Result.new(
          success: true,
          no_changes: true,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call).and_return(no_changes_result)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'reports Stripe is in sync' do
        output = capture_stdout { command.call(force: true) }
        expect(output).to include('No changes needed - Stripe is in sync with catalog')
      end
    end

    context 'with --dry-run flag' do
      let(:dry_run_result) do
        Billing::Operations::Catalog::Push::Result.new(
          success: true,
          dry_run: true,
          products_created: 2,
          products_updated: 1,
          prices_created: 4,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call).and_return(dry_run_result)
      end

      it 'passes dry_run: true to operation' do
        expect(Billing::Operations::Catalog::Push).to receive(:call) do |args|
          expect(args[:dry_run]).to be(true)
          dry_run_result
        end

        capture_stdout { command.call(dry_run: true) }
      end

      it 'shows DRY RUN in output' do
        output = capture_stdout { command.call(dry_run: true) }
        expect(output).to include('DRY RUN')
      end

      it 'reports would-be changes' do
        output = capture_stdout { command.call(dry_run: true) }
        expect(output).to include('Would')
        expect(output).to include('2 product(s)')
      end
    end

    context 'with --plan filter' do
      let(:filtered_result) do
        Billing::Operations::Catalog::Push::Result.new(
          success: true,
          products_created: 1,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call).and_return(filtered_result)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'passes plan_filter to operation' do
        expect(Billing::Operations::Catalog::Push).to receive(:call) do |args|
          expect(args[:plan_filter]).to eq('identity_plus_v1')
          filtered_result
        end

        capture_stdout { command.call(plan: 'identity_plus_v1', force: true) }
      end
    end

    context 'with --skip-prices flag' do
      let(:no_prices_result) do
        Billing::Operations::Catalog::Push::Result.new(
          success: true,
          products_created: 1,
          prices_created: 0,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call).and_return(no_prices_result)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'passes skip_prices: true to operation' do
        expect(Billing::Operations::Catalog::Push).to receive(:call) do |args|
          expect(args[:skip_prices]).to be(true)
          no_prices_result
        end

        capture_stdout { command.call(skip_prices: true, force: true) }
      end
    end

    context 'when operation fails' do
      let(:failure_result) do
        Billing::Operations::Catalog::Push::Result.new(
          success: false,
          errors: ['Catalog not found or failed to load'],
        )
      end

      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call).and_return(failure_result)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'displays error messages' do
        output = capture_stdout { command.call(force: true) }
        expect(output).to include('Error: Catalog not found')
      end
    end

    context 'successful push' do
      let(:success_result) do
        Billing::Operations::Catalog::Push::Result.new(
          success: true,
          products_created: 2,
          products_updated: 1,
          prices_created: 4,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call).and_return(success_result)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'reports completed changes' do
        output = capture_stdout { command.call(force: true) }
        expect(output).to include('Completed:')
        expect(output).to include('2 product(s)')
      end

      it 'shows next steps' do
        output = capture_stdout { command.call(force: true) }
        expect(output).to include('Catalog push complete!')
        expect(output).to include('bin/ots billing catalog pull')
      end
    end
  end
end
