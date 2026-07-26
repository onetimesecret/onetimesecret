# spec/cli/org_transfer_ownership_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org transfer-ownership` (#3731).
#
# Pure adapter coverage: org + new-owner resolution, the plan-then-prompt flow
# (the reason the op's dry_run defaults to true), the --yes / --json refusal, the
# interactive decline, and the op-status -> exit-code + operator-guidance
# mapping. The mutation, the ordering guarantee and the audit event are the op's
# job and are covered (against a real datastore) by
# spec/unit/onetime/operations/org/transfer_ownership_spec.rb, so here the op is
# stubbed at its constructor.
#
# This lives in its own file rather than appended to spec/cli/org_command_spec.rb
# because that file is owned by a concurrent lane.
#
# Run: bundle exec rspec spec/cli/org_transfer_ownership_command_spec.rb

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

  # The interactive path calls the op TWICE — once to build the plan
  # (dry_run: true), once to apply. Hand back whichever result the example
  # configured for that phase, and record the constructor args in order.
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
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_nope', 'new@example.com', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_nope')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'exits 1 when the new owner cannot be resolved' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'nope@example.com', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Customer not found: nope@example.com')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'refuses an anonymous new owner (ADR-023: never fabricate one)' do
      allow(new_owner).to receive(:anonymous?).and_return(true)

      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('anonymous customer')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end

    it 'resolves both parties BEFORE prompting' do
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'nope@example.com')

      expect(last_exit_code).to eq(1)
      expect($stdin).not_to have_received(:gets)
    end
  end

  describe 'plan-then-prompt (why the op dry-runs by default)' do
    it 'prints the dry-run plan, including the demotion count, before asking' do
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

      expect(output[:stdout]).to include('DRY RUN — nothing has been written yet')
      expect(output[:stdout]).to include('Current owner: ur_old_ext')
      expect(output[:stdout]).to include('Would demote:  1 owner membership(s): ur_old_ext')
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true, false])
    end

    it 'aborts without applying when the confirmation is declined' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Aborted.')
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
    end

    it 'skips the plan pass entirely under --yes' do
      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

      expect(op_calls.map { |args| args[:dry_run] }).to eq([false])
    end

    it 'refuses to transfer without --yes in --json mode' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['error'])
        .to eq('Refusing to transfer ownership without --yes in --json mode')
      expect(Onetime::Operations::Org::TransferOwnership).not_to have_received(:new)
    end
  end

  describe 'op invocation' do
    it 'passes the resolved objects, the CLI sentinel actor and demote_to through' do
      run_cli_command_quietly(
        'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes', '--demote-to', 'MEMBER'
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
      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

      expect(op_calls.last[:demote_to]).to eq('admin')
    end

    it 'never audits from the adapter' do
      allow(Onetime::AdminAuditEvent).to receive(:record)

      run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  describe 'output' do
    it 'reports the transfer and the demotions on the text path, exiting 0' do
      output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

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
        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

        expect(last_exit_code).to eq(0)
        expect(output[:stdout]).to include('owner (none) -> ur_new_ext')
        expect(output[:stdout]).to include('org doctor check 1')
      end
    end

    it 'emits the flat payload and exits 0 on --json --yes' do
      output = run_cli_command_quietly(
        'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes', '--json'
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

    context 'when the plan comes back :no_change' do
      let(:plan_result) { result_with(status: :no_change, dry_run: true, demoted: []) }

      it 'reports it without applying or prompting, and exits 0' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

        expect(last_exit_code).to eq(0)
        expect(output[:stdout]).to include('n****r@example.com is already the sole owner of on_org_ext')
        expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
        expect($stdin).not_to have_received(:gets)
      end
    end
  end

  describe 'refusals (identical guidance on the plan pass and the applied pass)' do
    context 'when the target is not a member (D28)' do
      let(:plan_result)    { result_with(status: :not_member, dry_run: true, demoted: []) }
      let(:applied_result) { result_with(status: :not_member, dry_run: false, demoted: []) }

      it 'points at `memberships add` and exits 1 on the interactive path — before any prompt' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('is not an active member')
        expect(output[:stdout]).to include('bin/ots memberships add')
        expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
        expect($stdin).not_to have_received(:gets)
      end

      it 'points at `memberships add` and exits 1 on the --yes path' do
        output = run_cli_command_quietly('org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('bin/ots memberships add')
      end

      it 'exits 1 with the refusal payload on the json path' do
        output = run_cli_command_quietly(
          'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes', '--json'
        )

        expect(last_exit_code).to eq(1)
        expect(JSON.parse(output[:stdout])['status']).to eq('not_member')
      end
    end

    context 'when --demote-to is not a demotable role' do
      let(:applied_result) { result_with(status: :invalid_role, dry_run: false, demoted: []) }

      it 'rejects it with the allowed values' do
        output = run_cli_command_quietly(
          'org', 'transfer-ownership', 'on_org_ext', 'new@example.com', '--yes', '--demote-to', 'owner'
        )

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('--demote-to must be one of: admin, member')
      end
    end
  end
end
