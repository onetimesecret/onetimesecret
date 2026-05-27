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
                  skipped_no_plan: 0, skipped_up_to_date: 0, skipped_plan_filter: 0,
                  memberships_succeeded: 0, memberships_failed: 0, orgs_cascaded: 0,
                  errors: [])
    Billing::Operations::MaterializePlansResult.new(
      scanned: scanned,
      succeeded: succeeded,
      failed: failed,
      skipped_no_plan: skipped_no_plan,
      skipped_up_to_date: skipped_up_to_date,
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

  describe 'argument validation' do
    it 'requires either --all or --plan' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)

      output = run_command

      expect(output).to include('Must specify --all or --plan')
      expect(Billing::Operations::MaterializePlans).not_to have_received(:call)
    end
  end

  describe 'option forwarding' do
    it 'forwards --plan, --stale, --force, --include-memberships, and dry_run to the operation' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(succeeded: 1))

      run_command(plan: 'identity_plus_v1', stale: true, force: true,
                  include_memberships: true, run: true)

      expect(Billing::Operations::MaterializePlans).to have_received(:call).with(
        hash_including(
          plan_filter: 'identity_plus_v1',
          stale: true,
          force: true,
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

    it 'shows (force) in the scope when --force is set' do
      output = run_command(all: true, force: true)
      expect(output).to include('(force)')
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

    it 'shows verbose error details when --verbose is set' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(stub_result(failed: 1, errors: [{ org_extid: 'org_x', reason: 'plan missing' }]))

      output = run_command(all: true, run: true, verbose: true)
      expect(output).to include('org_x')
      expect(output).to include('plan missing')
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
    it 'renders verbose per-org lines from progress events' do
      allow(Billing::Operations::MaterializePlans).to receive(:call) do |**, &blk|
        blk.call(
          Billing::Operations::MaterializePlansEvent.new(
            event: :materialized, org_extid: 'org_v', planid: 'p1',
            entitlements_count: 4, cascade: nil, reason: nil,
          ),
        )
        stub_result(succeeded: 1)
      end

      output = run_command(all: true, run: true, verbose: true)
      expect(output).to include('Materialized: org_v')
      expect(output).to include('p1')
    end

    it 'shows cascade hint in dry-run preview when --include-memberships is set' do
      allow(Billing::Operations::MaterializePlans).to receive(:call) do |**, &blk|
        blk.call(
          Billing::Operations::MaterializePlansEvent.new(
            event: :would_materialize, org_extid: 'org_v', planid: 'p1',
            entitlements_count: 4, cascade: nil, reason: nil,
          ),
        )
        stub_result(succeeded: 1)
      end

      output = run_command(all: true, include_memberships: true, verbose: true)
      expect(output).to include('Would materialize: org_v')
      expect(output).to include('(+memberships cascade)')
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
