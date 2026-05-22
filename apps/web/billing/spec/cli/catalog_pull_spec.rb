# apps/web/billing/spec/cli/catalog_pull_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing catalog pull` CLI wrapper.
#
# These test the CLI's public interface and delegation to operations.
# For detailed logic tests, see: spec/operations/catalog/pull_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_pull_command'

RSpec.describe 'Billing Catalog Pull CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingCatalogPullCommand.new }

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

      it 'exits early without pulling' do
        expect(Billing::Operations::Catalog::Pull).not_to receive(:call)
        command.call
      end
    end

    context 'successful pull' do
      let(:success_result) do
        Billing::Operations::Catalog::Pull::Result.new(
          success: true,
          plans_synced: 5,
          config_plans_loaded: 2,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(success_result)
      end

      it 'reports number of plans pulled' do
        output = capture_stdout { command.call }
        expect(output).to include('Successfully pulled 5 plan(s) from Stripe')
      end

      it 'reports config-only plans when present' do
        output = capture_stdout { command.call }
        expect(output).to include('Upserted 2 config-only plan(s)')
      end

      it 'shows next steps after successful pull' do
        output = capture_stdout { command.call }
        expect(output).to include('bin/ots billing plans')
      end

      it 'passes progress callback to operation' do
        expect(Billing::Operations::Catalog::Pull).to receive(:call) do |args|
          expect(args[:progress]).to be_a(Method)
          success_result
        end

        capture_stdout { command.call }
      end
    end

    context 'with --clear flag' do
      let(:cleared_result) do
        Billing::Operations::Catalog::Pull::Result.new(
          success: true,
          plans_synced: 3,
          cache_cleared: true,
        )
      end

      before do
        allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(cleared_result)
      end

      it 'passes clear_cache: true to operation' do
        expect(Billing::Operations::Catalog::Pull).to receive(:call) do |args|
          expect(args[:clear_cache]).to be(true)
          cleared_result
        end

        capture_stdout { command.call(clear: true) }
      end
    end

    context 'when operation fails' do
      let(:failure_result) do
        Billing::Operations::Catalog::Pull::Result.new(
          success: false,
          errors: ['Stripe error: Invalid API key'],
        )
      end

      before do
        allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(failure_result)
      end

      it 'displays error messages' do
        output = capture_stdout { command.call }
        expect(output).to include('Error: Stripe error: Invalid API key')
      end
    end
  end

  describe '#show_progress (private)' do
    it 'prints progress message with carriage return for overwriting' do
      output = capture_stdout do
        command.send(:show_progress, 'Processing plan 1 of 5...')
      end

      expect(output).to start_with("\r")
      expect(output).to include('Processing plan 1 of 5...')
    end
  end
end
