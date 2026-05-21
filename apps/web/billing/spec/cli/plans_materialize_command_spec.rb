# apps/web/billing/spec/cli/plans_materialize_command_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing plans materialize`.
#
# Tests the --force option which re-materializes entitlements
# even when they are already up to date.
#
# Run: pnpm run test:rspec apps/web/billing/spec/cli/plans_materialize_command_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/plans_materialize_command'

RSpec.describe 'Billing Plans Materialize CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingPlansMaterializeCommand.new }

  def run_command(**kwargs)
    old_stdout = $stdout
    $stdout    = StringIO.new
    command.call(**kwargs)
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  before do
    allow(command).to receive(:boot_application!)
  end

  describe '--help' do
    it 'documents the --force option' do
      output = run_command(help: true)

      expect(output).to include('--force')
      expect(output).to include('Force re-materialization')
    end
  end

  describe '--force option' do
    let(:mock_org) { instance_double(Onetime::Organization) }
    let(:mock_plan) { instance_double(Billing::Plan) }
    let(:mock_instances) { instance_double(Familia::SortedSet) }
    let(:mock_entitlements) { double('entitlements') }

    before do
      allow(Onetime::Organization).to receive(:instances).and_return(mock_instances)
      allow(mock_instances).to receive(:element_count).and_return(1)
      allow(mock_instances).to receive(:each_record).and_yield(mock_org)

      allow(mock_org).to receive(:extid).and_return('org_test123')
      allow(mock_org).to receive(:planid).and_return('test_plan_v1')

      allow(mock_plan).to receive(:plan_id).and_return('test_plan_v1')
      allow(mock_plan).to receive(:entitlements).and_return(mock_entitlements)
      allow(mock_entitlements).to receive(:size).and_return(5)

      allow(Billing::Plan).to receive(:list_plans).and_return([mock_plan])
    end

    context 'when org is already up to date' do
      before do
        allow(mock_org).to receive(:entitlements_materialized?).and_return(true)
        allow(mock_org).to receive(:entitlements_stale?).and_return(false)
      end

      it 'skips the org without --force (dry run)' do
        output = run_command(all: true, run: false)

        # Stats show 1 skipped, 0 materialized
        expect(output).to include('Skipped (up to date):')
        expect(output).to match(/Skipped \(up to date\):\s+1/)
        expect(output).to match(/Materialized:\s+0/)
        expect(output).not_to include('Would materialize')
      end

      it 'processes the org with --force (dry run)' do
        output = run_command(all: true, force: true, run: false)

        expect(output).to include('Would materialize')
        expect(output).to include('org_test123')
        # Stats show 1 materialized, 0 skipped
        expect(output).to match(/Materialized:\s+1/)
        expect(output).to match(/Skipped \(up to date\):\s+0/)
      end

      it 'materializes the org with --force --run' do
        allow(mock_org).to receive(:materialize_entitlements_from_plan)

        output = run_command(all: true, force: true, run: true)

        expect(mock_org).to have_received(:materialize_entitlements_from_plan).with(mock_plan)
        expect(output).to include('Materialized:')
      end

      it 'shows (force) in the scope banner' do
        output = run_command(all: true, force: true, run: false)

        expect(output).to include('(force)')
      end
    end

    context 'when using --stale with --force' do
      before do
        allow(mock_org).to receive(:entitlements_materialized?).and_return(true)
        allow(mock_org).to receive(:entitlements_stale?).and_return(false)
      end

      it '--force overrides --stale skip logic' do
        output = run_command(all: true, stale: true, force: true, run: false)

        expect(output).to include('Would materialize')
        # Stats show 1 materialized, 0 skipped
        expect(output).to match(/Materialized:\s+1/)
        expect(output).to match(/Skipped \(up to date\):\s+0/)
      end
    end
  end
end
