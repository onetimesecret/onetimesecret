# spec/cli/org_transfer_ownership_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org transfer-ownership` (#3731).
#
# Pure adapter coverage: org + new-owner resolution, the dry-run default
# (nothing written without --apply, no prompt), the --apply/--dry-run
# contradiction, and the op-status -> exit-code + operator-guidance mapping. The mutation, the ordering guarantee and the audit event are the op's
# job and are covered (against a real datastore) by
# spec/unit/onetime/operations/org/transfer_ownership_spec.rb, so here the op is
# stubbed at its constructor.
#
# This lives in its own file rather than appended to spec/cli/org_command_spec.rb
# because that file is owned by a concurrent lane.
#
# Run: tests/lanes/run unit --only spec/cli/org_transfer_ownership_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/transfer_ownership_command'

RSpec.describe 'Org Transfer Ownership Command', type: :cli do
  let(:organization) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      display_name: 'Test Org',
    )
  end

  let(:new_owner) do
    double(
      'Customer',
      extid: 'ur_new_ext',
      objid: 'cust-obj-new',
      custid: 'cust-obj-new',
      anonymous?: false,
      obscure_email: 'n****r@example.com',
    )
  end

  def result_with(status:, dry_run:, demoted: ['ur_old_ext'], **overrides)
    Onetime::Operations::Org::TransferOwnership::Result.new(
      **{
        status: status,
        org_id: 'on_org_ext',
        from_owner_id: 'ur_old_ext',
        from_owner_role_after: 'admin',
        to_owner_id: 'ur_new_ext',
        demoted: demoted,
        orphaned_owner: false,
        dry_run: dry_run,
      }.merge(overrides)
    )
  end

  # Hand back the plan for a dry run and the receipt for an applied run, and
  # record the constructor args in order.
  let(:plan_result)    { result_with(status: :planned, dry_run: true) }
  let(:applied_result) { result_with(status: :success, dry_run: false) }
  let(:op_calls)       { [] }

  before do
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Organization).to receive(:load).and_return(nil)

    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email)
      .with('new@example.com').and_return(new_owner)

    allow(Onetime::Operations::Org::TransferOwnership).to receive(:new) do |args|
      op_calls << args
      instance_double(
        Onetime::Operations::Org::TransferOwnership,
        call: args[:dry_run] ? plan_result : applied_result,
      )
    end
  end

  describe 'resolution' do
    it 'requires both arguments' do
      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext')

      expect(last_exit_code).to eq(1)
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'exits 1 when the org cannot be resolved' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_nope', 'new@example.com', '--apply')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_nope')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'exits 1 when the new owner cannot be resolved' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'nope@example.com', '--apply')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Customer not found: nope@example.com')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'refuses an anonymous new owner (ADR-023: never fabricate one)' do
      allow(new_owner).to receive(:anonymous?).and_return(true)

      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('anonymous customer')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

  end

  describe 'dry run (the default)' do
    it 'prints the plan, including the demotion count, and writes nothing, never prompting' do
      allow($stdin).to receive(:gets)

      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('DRY RUN — nothing was written')
      expect(output[:stdout]).to include('Current owner: ur_old_ext')
      expect(output[:stdout]).to include('Would demote:  1 owner membership(s): ur_old_ext')
      expect(output[:stdout]).to include('Re-run with --apply to transfer.')
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
      expect($stdin).not_to have_received(:gets)
    end

    it 'calls the op once, applied, under --apply' do
      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

      expect(op_calls.map { |args| args[:dry_run] }).to eq([false])
    end

    it 'treats --yes as --apply' do
      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

      expect(op_calls.map { |args| args[:dry_run] }).to eq([false])
    end

    it 'refuses --apply with --dry-run before calling the op' do
      output = run_cli_command_quietly(
        'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply', '--dry-run'
      )

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('--apply and --dry-run are contradictory')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'emits the plan as JSON without --apply and exits 0' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--json')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])).to include('status' => 'planned', 'dry_run' => true)
    end
  end

  describe 'op invocation' do
    it 'passes the resolved objects, the CLI sentinel actor and demote_to through' do
      run_cli_command_quietly(
        'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply', '--demote-to', 'MEMBER'
      )

      expect(op_calls.last).to include(
        org: organization,
        new_owner: new_owner,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        demote_to: 'member', # normalized by the adapter
        dry_run: false,
      )
    end

    it "defaults --demote-to to 'admin' (D27 — no remove sentinel)" do
      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

      expect(op_calls.last[:demote_to]).to eq('admin')
    end

    it 'never audits from the adapter' do
      allow(Onetime::ColonelAuditEvent).to receive(:record)

      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'output' do
    it 'reports the transfer and the demotions on the text path, exiting 0' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('on_org_ext: owner ur_old_ext -> ur_new_ext (n****r@example.com)')
      expect(output[:stdout]).to include("Demoted 1 previous owner(s) to 'admin': ur_old_ext")
    end

    # Result is a Data value object (frozen), so every variant is built rather
    # than stubbed — partial-doubling a frozen object is impossible.
    context 'when the previous owner_id was orphaned (D30)' do
      let(:applied_result) do
        result_with(status: :success, dry_run: false, orphaned_owner: true, from_owner_id: nil)
      end

      it 'surfaces the repair' do
        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

        expect(last_exit_code).to eq(0)
        expect(output[:stdout]).to include('owner (none) -> ur_new_ext')
        expect(output[:stdout]).to include('org doctor check 1')
      end
    end

    it 'emits the flat payload and exits 0 on --json --apply' do
      output = run_cli_command_quietly(
        'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply', '--json'
      )

      payload = JSON.parse(output[:stdout])
      expect(last_exit_code).to eq(0)
      expect(payload['status']).to eq('success')
      expect(payload['org_id']).to eq('on_org_ext')
      expect(payload['from_owner_id']).to eq('ur_old_ext')
      expect(payload['to_owner_id']).to eq('ur_new_ext')
      expect(payload['new_owner_email']).to eq('n****r@example.com')
      expect(payload['demoted']).to eq(['ur_old_ext'])
      expect(payload['demoted_to']).to eq('admin')
    end

    context 'when the dry run comes back :no_change' do
      let(:plan_result) { result_with(status: :no_change, dry_run: true, demoted: []) }

      it 'reports it and exits 0' do
        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

        expect(last_exit_code).to eq(0)
        expect(output[:stdout]).to include('n****r@example.com is already the sole owner of on_org_ext')
        expect(output[:stdout]).not_to include('Re-run with --apply')
        expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
      end
    end
  end

  describe 'refusals (identical guidance on a dry run and an applied run)' do
    context 'when the target is not a member (D28)' do
      let(:plan_result)    { result_with(status: :not_member, dry_run: true, demoted: []) }
      let(:applied_result) { result_with(status: :not_member, dry_run: false, demoted: []) }

      it 'points at `memberships add` and exits 1 on a dry run' do
        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('n****r@example.com is not an active member of on_org_ext (Test Org)')
        expect(output[:stdout]).to include('bin/ots memberships add')
        expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
      end

      it 'points at `memberships add` and exits 1 on the --apply path' do
        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('bin/ots memberships add')
      end

      it 'exits 1 with the refusal payload on the json path' do
        output = run_cli_command_quietly(
          'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply', '--json'
        )

        expect(last_exit_code).to eq(1)
        expect(JSON.parse(output[:stdout])['status']).to eq('not_member')
      end
    end

    context 'when --demote-to is not a demotable role' do
      let(:applied_result) { result_with(status: :invalid_role, dry_run: false, demoted: []) }

      it 'rejects it with the allowed values' do
        output = run_cli_command_quietly(
          'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--apply', '--demote-to', 'owner'
        )

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('--demote-to must be one of: admin, member')
      end
    end
  end
end
