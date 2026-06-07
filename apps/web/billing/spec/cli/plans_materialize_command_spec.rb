# apps/web/billing/spec/cli/plans_materialize_command_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing plans materialize`.
#
# The CLI command is a thin wrapper over Billing::Operations::MaterializePlans.
# These specs verify option parsing, the rendered banner / stats / next-steps,
# and that flags are forwarded to the operation. Per-org materialization logic
# is covered in spec/operations/materialize_plans_spec.rb.
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

  def stub_result(succeeded: 0, failed: 0, scanned: 1,
                  skipped_no_plan: 0, skipped_plan_filter: 0,
                  memberships_succeeded: 0, memberships_failed: 0, orgs_cascaded: 0,
                  errors: [])
    Billing::Operations::MaterializePlansResult.new(
      scanned: scanned,
      succeeded: succeeded,
      failed: failed,
      skipped_no_plan: skipped_no_plan,
      skipped_plan_filter: skipped_plan_filter,
      memberships_succeeded: memberships_succeeded,
      memberships_failed: memberships_failed,
      orgs_cascaded: orgs_cascaded,
      errors: errors,
    )
  end

  before do
    allow(command).to receive(:boot_application!)
    instances = instance_double(Familia::SortedSet, element_count: 1)
    allow(Onetime::Organization).to receive(:instances).and_return(instances)
  end

  describe '--help' do
    it 'documents the --include-memberships option' do
      output = run_command(help: true)

      expect(output).to include('--include-memberships')
      expect(output).to include('Cascade re-materialization')
    end

    it 'documents the --quiet and repurposed --verbose flags' do
      output = run_command(help: true)

      expect(output).to include('--quiet')
      expect(output).to include('per-membership detail')
    end

    it 'does not advertise the removed --force / --stale flags' do
      output = run_command(help: true)

      expect(output).not_to include('--force')
      expect(output).not_to include('--stale')
    end
  end

  describe 'argument validation' do
    it 'requires either --all or --plan' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)

      output = run_command

      expect(output).to include('Must specify --all or --plan')
      expect(Billing::Operations::MaterializePlans).not_to have_received(:call)
    end
  end

  describe 'option forwarding' do
    it 'forwards --plan, --include-memberships, and dry_run to the operation' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1))

      run_command(plan: 'identity_plus_v1', include_memberships: true, run: true)

      expect(Billing::Operations::MaterializePlans).to have_received(:call).with(
        hash_including(
          plan_filter: 'identity_plus_v1',
          include_memberships: true,
          dry_run: false,
        ),
      )
    end

    it 'defaults to dry_run when --run is not passed' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1))

      run_command(all: true)

      expect(Billing::Operations::MaterializePlans).to have_received(:call).with(
        hash_including(dry_run: true),
      )
    end
  end

  describe 'banner' do
    before do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1))
    end

    it 'shows DRY RUN MODE when --run is not set' do
      output = run_command(all: true)
      expect(output).to include('DRY RUN MODE')
    end

    it 'shows the cascade scope when --include-memberships is set' do
      output = run_command(all: true, include_memberships: true)
      expect(output).to include('+ memberships cascade')
    end
  end

  describe 'stats rendering' do
    it 'renders succeeded count' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1))

      output = run_command(all: true, run: true)
      expect(output).to match(/Succeeded:\s+1/)
    end

    it 'renders failed count when failures occurred' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(failed: 1, errors: [{ org_extid: 'org_x', reason: 'boom' }]))

      output = run_command(all: true, run: true)
      expect(output).to match(/Failed:\s+1/)
      expect(output).to include('Errors:')
    end

    it 'renders membership stats when --include-memberships is set on real run' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1, orgs_cascaded: 1, memberships_succeeded: 3))

      output = run_command(all: true, include_memberships: true, run: true)
      expect(output).to match(/Orgs cascaded:\s+1/)
      expect(output).to match(/Memberships materialized:\s+3/)
    end

    it 'shows error details by default (verbosity = :default)' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(failed: 1, errors: [{ org_extid: 'org_x', reason: 'plan missing' }]))

      output = run_command(all: true, run: true)
      expect(output).to include('org_x')
      expect(output).to include('plan missing')
    end

    it 'suppresses error details under --quiet' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(failed: 1, errors: [{ org_extid: 'org_x', reason: 'plan missing' }]))

      output = run_command(all: true, run: true, quiet: true)
      expect(output).not_to include('plan missing')
      # The failure count still appears in the summary; only the per-error list is hidden.
      expect(output).to match(/Failed:\s+1/)
    end
  end

  describe 'next-steps suggestion' do
    it 'includes --include-memberships in the suggested command' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1))

      output = run_command(all: true, include_memberships: true)
      expect(output).to include('bin/ots billing plans materialize --all --run --include-memberships')
    end

    it 'omits next-steps when nothing would be materialized' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 0))

      output = run_command(all: true)
      expect(output).not_to include('To execute materialization')
    end
  end

  describe 'progress streaming' do
    def stub_with_event(event)
      allow(Billing::Operations::MaterializePlans).to receive(:call) do |**, &blk|
        blk.call(event)
        stub_result(succeeded: 1)
      end
    end

    it 'renders per-org lines BY DEFAULT (no flag needed) so audit logs capture progress' do
      stub_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_v', planid: 'p1',
          entitlements_count: 4, cascade: nil, reason: nil,
        ),
      )

      output = run_command(all: true, run: true)
      expect(output).to include('Materialized: org_v')
      expect(output).to include('p1')
    end

    it 'shows cascade hint in dry-run preview when --include-memberships is set' do
      stub_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :would_materialize, org_extid: 'org_v', planid: 'p1',
          entitlements_count: 4, cascade: nil, reason: nil,
        ),
      )

      output = run_command(all: true, include_memberships: true)
      expect(output).to include('Would materialize: org_v')
      expect(output).to include('(+memberships cascade)')
    end

    it 'shows cascade summary (M/T memberships) on the per-org line after a cascaded run' do
      stub_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_v', planid: 'p1',
          entitlements_count: 4,
          cascade: { success: 3, failed: 0, total: 3, details: [] },
          reason: nil,
        ),
      )

      output = run_command(all: true, include_memberships: true, run: true)
      expect(output).to include('Materialized: org_v')
      expect(output).to include('cascaded 3/3 memberships')
    end

    it '--verbose adds per-membership detail lines under each cascaded org' do
      stub_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_v', planid: 'p1',
          entitlements_count: 4,
          cascade: {
            success: 2, failed: 0, total: 2,
            details: [
              { objid: 'mem_aaa', role: 'owner',  planid: 'p1', entitlements_count: 12, status: :ok, error: nil },
              { objid: 'mem_bbb', role: 'member', planid: 'p1', entitlements_count: 4,  status: :ok, error: nil },
            ],
          },
          reason: nil,
        ),
      )

      output = run_command(all: true, include_memberships: true, run: true, verbose: true)
      expect(output).to include('mem_aaa')
      expect(output).to include('role=owner')
      expect(output).to include('plan=p1')
      expect(output).to include('12 entitlements')
      expect(output).to include('mem_bbb')
    end

    it '--quiet suppresses per-org lines (banner + summary only)' do
      stub_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_v', planid: 'p1',
          entitlements_count: 4, cascade: nil, reason: nil,
        ),
      )

      output = run_command(all: true, run: true, quiet: true)
      expect(output).not_to include('Materialized: org_v')
      # Banner + summary still present
      expect(output).to include('Entitlement Materialization')
      expect(output).to match(/Succeeded:\s+1/)
    end
  end

  describe 'edge cases' do
    it 'reports zero organizations gracefully' do
      empty = instance_double(Familia::SortedSet, element_count: 0)
      allow(Onetime::Organization).to receive(:instances).and_return(empty)
      allow(Billing::Operations::MaterializePlans).to receive(:call)

      output = run_command(all: true, run: true)

      expect(output).to include('No organizations found')
      expect(Billing::Operations::MaterializePlans).not_to have_received(:call)
    end
  end
end
