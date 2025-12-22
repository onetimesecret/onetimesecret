# apps/web/billing/spec/cli/catalog_pull_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_pull_command'

RSpec.describe 'Billing Catalog Pull CLI', :billing_cli, :unit do
  subject(:command) { Onetime::CLI::BillingCatalogPullCommand.new }

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
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
        expect(Billing::Plan).not_to receive(:refresh_from_stripe)
        command.call
      end
    end

    context 'successful pull' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(5)
      end

      it 'reports number of plans pulled' do
        output = capture_stdout { command.call }

        expect(output).to include('Pulling from Stripe to Redis cache')
        expect(output).to include('Successfully pulled 5 plan(s) to cache')
      end

      it 'shows next steps after successful pull' do
        output = capture_stdout { command.call }
        expect(output).to include('bin/ots billing plans')
      end

      it 'passes progress callback to refresh_from_stripe' do
        expect(Billing::Plan).to receive(:refresh_from_stripe) do |progress:|
          expect(progress).to be_a(Method)
          5
        end

        capture_stdout { command.call }
      end
    end

    context 'with --clear flag' do
      before do
        allow(Billing::Plan).to receive(:clear_cache)
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(3)
      end

      it 'clears cache before pulling' do
        expect(Billing::Plan).to receive(:clear_cache).ordered
        expect(Billing::Plan).to receive(:refresh_from_stripe).ordered

        capture_stdout { command.call(clear: true) }
      end

      it 'reports cache cleared' do
        output = capture_stdout { command.call(clear: true) }

        expect(output).to include('Clearing existing plan cache')
        expect(output).to include('Cache cleared')
      end
    end

    context 'when Stripe API fails' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
          .and_raise(Stripe::AuthenticationError.new('Invalid API key'))
      end

      it 'displays error with troubleshooting tips' do
        output = capture_stdout { command.call }

        expect(output).to include('Pull failed')
        expect(output).to include('Troubleshooting')
        expect(output).to include('STRIPE_KEY')
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
          .and_raise(StandardError.new('Connection timeout'))
      end

      it 'displays error message' do
        output = capture_stdout { command.call }
        expect(output).to include('Error during pull: Connection timeout')
      end
    end
  end

  describe '#show_progress (private)' do
    it 'prints progress message with carriage return for overwriting' do
      output = capture_stdout do
        command.send(:show_progress, 'Processing plan 1 of 5...')
      end

      # Should start with carriage return for line overwriting
      expect(output).to start_with("\r")
      expect(output).to include('Processing plan 1 of 5...')
    end
  end
end
