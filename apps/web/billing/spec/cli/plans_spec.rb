# apps/web/billing/spec/cli/plans_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/plans_command'

RSpec.describe 'Billing Plans CLI Commands', :billing_cli, :stripe_mock, :unit do
  let(:stripe_client) { Billing::StripeClient.new }

  describe Onetime::CLI::BillingPlansCommand do
    subject(:command) { described_class.new }

    # Sample plan data structure for mocking
    let(:sample_plan) do
      OpenStruct.new(
        plan_id: 'single_team_monthly_us',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'US',
        capabilities: '["create_secrets","create_team"]',
      )
    end

    let(:sample_plan_eu) do
      OpenStruct.new(
        plan_id: 'multi_team_yearly_eu',
        tier: 'multi_team',
        interval: 'year',
        amount: '99900',
        currency: 'eur',
        region: 'EU',
        capabilities: '["create_secrets","create_team","custom_domains"]',
      )
    end

    describe '#call (list plans)' do
      before do
        allow(Billing::Plan).to receive(:list_plans).and_return([sample_plan])
      end

      it 'displays column headers' do
        output = capture_stdout { command.call }
        expect(output).to match(/PLAN ID.*TIER.*INTERVAL.*AMOUNT.*REGION.*CAPS/)
      end

      it 'displays separator line after headers' do
        output = capture_stdout { command.call }
        expect(output).to match(/^-{90}$/)
      end

      it 'formats plan rows with proper alignment' do
        output = capture_stdout { command.call }
        # Plan ID should be displayed
        expect(output).to include('single_team_monthly')
        # Tier should be displayed
        expect(output).to include('single_team')
        # Interval should be displayed
        expect(output).to include('month')
        # Amount should be formatted
        expect(output).to match(/USD 29\.00/)
      end

      it 'displays plan count' do
        output = capture_stdout { command.call }
        expect(output).to match(/Total: 1 plan entr/)
      end

      it 'displays multiple plans when available' do
        allow(Billing::Plan).to receive(:list_plans).and_return([sample_plan, sample_plan_eu])
        output = capture_stdout { command.call }

        expect(output).to include('single_team_monthly')
        expect(output).to include('multi_team_yearly')
        expect(output).to match(/Total: 2 plan entr/)
      end

      it 'displays capability count' do
        output = capture_stdout { command.call }
        # Sample plan has 2 capabilities
        expect(output).to match(/\s+2\s*$/)
      end

      context 'when cache is empty' do
        before do
          allow(Billing::Plan).to receive(:list_plans).and_return([])
        end

        it 'displays empty state message' do
          output = capture_stdout { command.call }
          expect(output).to include('No plan entries found')
        end

        it 'suggests refresh when no plans found' do
          output = capture_stdout { command.call }
          expect(output).to include('Run with --refresh to sync from Stripe')
        end

        it 'does not display headers when empty' do
          output = capture_stdout { command.call }
          expect(output).not_to include('PLAN ID')
          expect(output).not_to include('TIER')
        end
      end

      context 'with --refresh option' do
        before do
          allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(2)
          allow(Billing::Plan).to receive(:list_plans).and_return([sample_plan, sample_plan_eu])
        end

        it 'displays refresh progress message' do
          output = capture_stdout { command.call(refresh: true) }
          expect(output).to include('Refreshing plans from Stripe')
        end

        it 'displays refresh count' do
          output = capture_stdout { command.call(refresh: true) }
          expect(output).to match(/Refreshed 2 plan entr/)
        end

        it 'then displays refreshed plans' do
          output = capture_stdout { command.call(refresh: true) }
          expect(output).to include('Refreshing plans from Stripe')
          expect(output).to include('single_team_monthly')
          expect(output).to include('multi_team_yearly')
        end

        it 'adds blank line after refresh messages' do
          output           = capture_stdout { command.call(refresh: true) }
          lines            = output.split("\n")
          refresh_line_idx = lines.index { |l| l.include?('Refreshed') }
          expect(lines[refresh_line_idx + 1]).to eq('')
        end
      end

      context 'error handling' do
        it 'handles Stripe API errors during refresh' do
          allow(Billing::Plan).to receive(:refresh_from_stripe)
            .and_raise(Stripe::InvalidRequestError.new('Invalid API key', 'api_key'))

          expect do
            capture_stdout { command.call(refresh: true) }
          end.to raise_error(Stripe::InvalidRequestError, /Invalid API key/)
        end

        it 'handles missing Stripe configuration gracefully' do
          allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(0)
          allow(Billing::Plan).to receive(:list_plans).and_return([])

          output = capture_stdout { command.call(refresh: true) }
          expect(output).to include('Refreshed 0 plan entries')
          expect(output).to include('No plan entries found')
        end

        it 'exits early when Stripe not configured', :code_smell, :integration, :stripe_sandbox_api do
          # This test requires actual missing Stripe config - integration test needed
          skip 'Requires testing with missing Stripe configuration'
        end
      end

      context 'format validation' do
        it 'truncates long plan IDs to 20 characters' do
          long_plan = OpenStruct.new(
            plan_id: 'a' * 30,
            tier: 'test',
            interval: 'month',
            amount: '1000',
            currency: 'usd',
            region: 'US',
            capabilities: '[]',
          )
          allow(Billing::Plan).to receive(:list_plans).and_return([long_plan])

          output = capture_stdout { command.call }
          # Should only show 20 characters
          expect(output).to match(/^#{'a' * 20}\s/)
          expect(output).not_to match(/#{long_plan.plan_id}/)
        end

        it 'formats USD amounts correctly' do
          output = capture_stdout { command.call }
          expect(output).to match(/USD 29\.00/)
        end

        it 'formats EUR amounts correctly' do
          allow(Billing::Plan).to receive(:list_plans).and_return([sample_plan_eu])
          output = capture_stdout { command.call }
          expect(output).to match(/EUR 999\.00/)
        end

        it 'handles zero-capability plans' do
          zero_cap_plan = OpenStruct.new(
            plan_id: 'basic_monthly_us',
            tier: 'basic',
            interval: 'month',
            amount: '0',
            currency: 'usd',
            region: 'US',
            capabilities: '[]',
          )
          allow(Billing::Plan).to receive(:list_plans).and_return([zero_cap_plan])

          output = capture_stdout { command.call }
          expect(output).to match(/\s+0.00\s*$/)
        end
      end
    end
  end

  # Helper to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout    = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
