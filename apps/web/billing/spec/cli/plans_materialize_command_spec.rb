# apps/web/billing/spec/cli/plans_materialize_command_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing plans materialize`.
#
# Tests the --force option (re-materializes entitlements even when they are
# already up to date) and the --include-memberships option (cascades
# re-materialization to all active memberships after each org).
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

    it 'documents the --include-memberships option' do
      output = run_command(help: true)

      expect(output).to include('--include-memberships')
      expect(output).to include('Cascade re-materialization')
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

  describe '--include-memberships option' do
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
      allow(mock_org).to receive(:entitlements_materialized?).and_return(false)

      allow(mock_plan).to receive(:plan_id).and_return('test_plan_v1')
      allow(mock_plan).to receive(:entitlements).and_return(mock_entitlements)
      allow(mock_entitlements).to receive(:size).and_return(5)

      allow(Billing::Plan).to receive(:list_plans).and_return([mock_plan])
    end

    it 'shows cascade indicator in dry-run output' do
      output = run_command(all: true, include_memberships: true, run: false)

      expect(output).to include('Would materialize')
      expect(output).to include('+memberships cascade')
      expect(output).to include('+ memberships cascade')
    end

    it 'does not call rematerialize_all_memberships! in dry-run' do
      allow(mock_org).to receive(:rematerialize_all_memberships!)

      run_command(all: true, include_memberships: true, run: false)

      expect(mock_org).not_to have_received(:rematerialize_all_memberships!)
    end

    it 'cascades to memberships when --run is set' do
      allow(mock_org).to receive(:materialize_entitlements_from_plan)
      allow(mock_org).to receive(:rematerialize_all_memberships!).and_return(
        { success: 3, failed: 0, total: 3 },
      )

      output = run_command(all: true, include_memberships: true, run: true)

      expect(mock_org).to have_received(:materialize_entitlements_from_plan).with(mock_plan)
      expect(mock_org).to have_received(:rematerialize_all_memberships!)
      expect(output).to match(/Orgs cascaded:\s+1/)
      expect(output).to match(/Memberships materialized:\s+3/)
    end

    it 'reports membership failures in stats and errors' do
      allow(mock_org).to receive(:materialize_entitlements_from_plan)
      allow(mock_org).to receive(:rematerialize_all_memberships!).and_return(
        { success: 2, failed: 1, total: 3 },
      )

      output = run_command(all: true, include_memberships: true, run: true)

      expect(output).to match(/Memberships materialized:\s+2/)
      expect(output).to match(/Memberships failed:\s+1/)
    end

    it 'does not cascade when flag is omitted' do
      allow(mock_org).to receive(:materialize_entitlements_from_plan)
      allow(mock_org).to receive(:rematerialize_all_memberships!)

      run_command(all: true, run: true)

      expect(mock_org).not_to have_received(:rematerialize_all_memberships!)
    end

    it 'does not cascade when org is skipped (up to date)' do
      allow(mock_org).to receive(:entitlements_materialized?).and_return(true)
      allow(mock_org).to receive(:entitlements_stale?).and_return(false)
      allow(mock_org).to receive(:materialize_entitlements_from_plan)
      allow(mock_org).to receive(:rematerialize_all_memberships!)

      run_command(all: true, include_memberships: true, run: true)

      expect(mock_org).not_to have_received(:materialize_entitlements_from_plan)
      expect(mock_org).not_to have_received(:rematerialize_all_memberships!)
    end

    it 'cascades after --force re-materialization' do
      allow(mock_org).to receive(:entitlements_materialized?).and_return(true)
      allow(mock_org).to receive(:entitlements_stale?).and_return(false)
      allow(mock_org).to receive(:materialize_entitlements_from_plan)
      allow(mock_org).to receive(:rematerialize_all_memberships!).and_return(
        { success: 4, failed: 0, total: 4 },
      )

      output = run_command(all: true, force: true, include_memberships: true, run: true)

      expect(mock_org).to have_received(:materialize_entitlements_from_plan).with(mock_plan)
      expect(mock_org).to have_received(:rematerialize_all_memberships!)
      expect(output).to match(/Memberships materialized:\s+4/)
    end

    it 'includes --include-memberships in next-steps suggestion' do
      output = run_command(all: true, include_memberships: true, run: false)

      expect(output).to include('--include-memberships')
      expect(output).to include('bin/ots billing plans materialize --all --run --include-memberships')
    end
  end
end
