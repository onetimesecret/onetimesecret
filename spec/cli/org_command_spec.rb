# spec/cli/org_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org …` (#3731).
#
# Covers the landing command's usage list and the `org reconcile` adapter:
# resolution, the --yes / --json refusal, the interactive decline, and the
# op-status -> exit-code mapping. The mutation itself is the op's job and is
# covered by spec/unit/onetime/operations/org/reconcile_spec.rb — here the op is
# stubbed at its constructor so these stay pure adapter tests.
#
# NOTE for later org PRs: append `describe` blocks to this file rather than
# creating a sibling spec, so the whole `org` surface stays in one place.
#
# Run: bundle exec rspec spec/cli/org_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/reconcile_command'

RSpec.describe 'Org Command', type: :cli do
  let(:organization) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      display_name: 'Test Org',
    )
  end

  let(:result) do
    Onetime::Operations::Org::Reconcile::Result.new(
      status: :materialized,
      org_id: 'on_org_ext',
      mode: 'entitlements_only',
      before: {
        planid: 'free_v1', subscription_status: nil,
        subscription_period_end: nil, materialized_count: 2
      },
      after: {
        planid: 'free_v1', subscription_status: nil,
        subscription_period_end: nil, materialized_count: 7
      },
      reason: nil,
      memberships: { success: 3, failed: 0, total: 3, failed_ids: [] },
      dry_run: false,
    )
  end

  let(:operation) { instance_double(Onetime::Operations::Org::Reconcile, call: result) }

  before do
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::Operations::Org::Reconcile).to receive(:new).and_return(operation)
  end

  describe 'without a subcommand' do
    before do
      allow(Onetime::Organization).to receive(:instances).and_return(double('Instances', size: 3))
    end

    it 'prints the count and every registered org verb' do
      output = run_cli_command_quietly('org')

      expect(output[:stdout]).to include('3 organizations')
      expect(output[:stdout]).to include('bin/ots org doctor')
      expect(output[:stdout]).to include('bin/ots org reconcile')
    end
  end

  describe 'reconcile subcommand' do
    it 'requires an ORG argument' do
      run_cli_command_quietly('org', 'reconcile')

      expect(last_exit_code).to eq(1)
      expect(Onetime::Operations::Org::Reconcile).not_to have_received(:new)
    end

    it 'exits 1 when the organization cannot be resolved' do
      output = run_cli_command_quietly('org', 'reconcile', 'nope', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: nope')
      expect(Onetime::Operations::Org::Reconcile).not_to have_received(:new)
    end

    it 'resolves by objid when the extid lookup misses' do
      allow(Onetime::Organization).to receive(:load).with('org-obj-1').and_return(organization)

      run_cli_command_quietly('org', 'reconcile', 'org-obj-1', '--yes')

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new)
    end

    it 'refuses to apply without --yes in --json mode' do
      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['error'])
        .to eq('Refusing to reconcile without --yes in --json mode')
      expect(Onetime::Operations::Org::Reconcile).not_to have_received(:new)
    end

    it 'aborts without calling the op when the confirmation is declined' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Aborted.')
      expect(Onetime::Operations::Org::Reconcile).not_to have_received(:new)
    end

    it 'applies after an interactive confirmation' do
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('org', 'reconcile', 'on_org_ext')

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new).with(
        org: organization,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        dry_run: false,
      )
    end

    it 'attributes the audit actor to the shared CLI sentinel, never a Customer' do
      run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes')

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new)
        .with(hash_including(actor: 'cli'))
    end

    it 'passes dry_run: true for --dry-run and needs no confirmation' do
      run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--dry-run')

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new)
        .with(hash_including(dry_run: true))
    end

    it 'prints the before/after diff on the text path' do
      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('entitlements_only')
      expect(output[:stdout]).to include('materialized_count')
    end

    it 'prints the membership-cascade counts on the text path (#3907)' do
      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes')

      expect(output[:stdout]).to include('Memberships:  3/3 re-materialized')
    end

    it 'flags a partial cascade with the failed membership ids (#3907)' do
      allow(operation).to receive(:call).and_return(
        result.with(memberships: { success: 1, failed: 2, total: 3, failed_ids: %w[mem_p mem_q] })
      )

      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes')

      expect(output[:stdout]).to include('1/3 re-materialized — 2 FAILED: mem_p, mem_q')
    end

    it 'prints no cascade line when the op reports none (dry run / skip / raised)' do
      allow(operation).to receive(:call).and_return(result.with(memberships: nil))

      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes')

      expect(output[:stdout]).not_to include('Memberships:')
    end

    it 'emits the flat Result payload and exits 0 on --json --yes' do
      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes', '--json')

      payload = JSON.parse(output[:stdout])
      expect(last_exit_code).to eq(0)
      expect(payload['status']).to eq('materialized')
      expect(payload['org_id']).to eq('on_org_ext')
      expect(payload['mode']).to eq('entitlements_only')
      expect(payload['after']['materialized_count']).to eq(7)
      expect(payload['memberships']).to eq('success' => 3, 'failed' => 0, 'total' => 3, 'failed_ids' => [])
    end

    it 'exits 1 when the org has no plan to reconcile against' do
      allow(operation).to receive(:call).and_return(
        result.with(status: :skipped_no_plan, reason: 'Organization has no planid')
      )

      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['status']).to eq('skipped_no_plan')
    end

    it 'exits 1 and reports the Stripe failure on the text path' do
      allow(operation).to receive(:call).and_return(
        result.with(status: :stripe_error, mode: 'stripe_sync', after: nil, reason: 'no such subscription')
      )

      output = run_cli_command_quietly('org', 'reconcile', 'on_org_ext', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Stripe error: no such subscription')
    end
  end
end
