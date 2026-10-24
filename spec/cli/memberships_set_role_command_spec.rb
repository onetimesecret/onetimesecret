# spec/cli/memberships_set_role_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots memberships set-role ORG CUSTOMER ROLE`.
#
# Covers the dry-run default (nothing written without --apply, no prompt) and
# the op-status -> exit-code mapping. The role change, re-materialization and
# audit events are the op's job
# (spec/unit/onetime/operations/memberships/set_role_spec.rb); here the op is
# stubbed at its constructor so these stay pure adapter tests.
#
# Run: tests/lanes/run unit --only spec/cli/memberships_set_role_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/memberships/shared'
require 'onetime/cli/memberships/set_role_command'

RSpec.describe 'Memberships Set Role Command', type: :cli do
  let(:organization) do
    double('Organization', objid: 'org-obj-1', extid: 'on_org_ext', display_name: 'Acme')
  end

  let(:member) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member', obscure_email: 'me***@example.com', anonymous?: false)
  end

  let(:status) { :dry_run }

  let(:result) do
    Onetime::Operations::Memberships::SetRole::Result.new(
      status: status, org_id: 'on_org_ext', customer_id: 'ur_member', from: 'member', to: 'admin',
    )
  end

  let(:set_role_op) { Onetime::Operations::Memberships::SetRole }

  before do
    allow(Onetime::Organization).to receive_messages(find_by_extid: nil, load: nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_member').and_return(member)
    allow(set_role_op).to receive(:new).and_return(instance_double(set_role_op, call: result))
  end

  describe 'dry run (the default)' do
    it 'asks the op for a dry run without --apply, never prompting' do
      allow($stdin).to receive(:gets)

      output = run_cli_command_quietly('memberships', 'set-role', 'on_org_ext', 'ur_member', 'ADMIN')

      expect(last_exit_code).to eq(0)
      expect(set_role_op).to have_received(:new).with(
        org: organization,
        customer: member,
        new_role: 'admin', # normalized by the adapter
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        reason: nil,
        dry_run: true,
      )
      expect($stdin).not_to have_received(:gets)
      expect(output[:stdout]).to include('Would change me***@example.com: member -> admin')
      expect(output[:stdout]).to include('Dry run - nothing written. Re-run with --apply to write.')
    end

    it 'emits dry_run: true in --json and exits 0' do
      output = run_cli_command_quietly('memberships', 'set-role', 'on_org_ext', 'ur_member', 'admin', '--json')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])).to include('status' => 'dry_run', 'dry_run' => true)
    end

    it 'refuses --apply with --dry-run before calling the op' do
      output = run_cli_command_quietly(
        'memberships', 'set-role', 'on_org_ext', 'ur_member', 'admin', '--apply', '--dry-run'
      )

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('--apply and --dry-run are contradictory')
      expect(set_role_op).not_to have_received(:new)
    end

    context 'when the member already has the role' do
      let(:result) do
        Onetime::Operations::Memberships::SetRole::Result.new(
          status: :no_change, org_id: 'on_org_ext', customer_id: 'ur_member', from: 'admin', to: 'admin',
        )
      end

      it 'says there is nothing to write and exits 0' do
        output = run_cli_command_quietly('memberships', 'set-role', 'on_org_ext', 'ur_member', 'admin')

        expect(last_exit_code).to eq(0)
        expect(output[:stdout]).to include("me***@example.com already has role 'admin'")
        expect(output[:stdout]).to include('Dry run - nothing to write.')
      end
    end

    context 'when the member is the last owner' do
      let(:status) { :last_owner }

      it 'exits 1 on the dry run too' do
        output = run_cli_command_quietly('memberships', 'set-role', 'on_org_ext', 'ur_member', 'member')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('Cannot demote the last remaining owner')
      end
    end
  end

  describe 'with --apply' do
    let(:status) { :success }

    it 'asks the op to write and threads --reason through' do
      output = run_cli_command_quietly(
        'memberships', 'set-role', 'on_org_ext', 'ur_member', 'admin', '--apply', '--reason', 'promoted'
      )

      expect(last_exit_code).to eq(0)
      expect(set_role_op).to have_received(:new).with(hash_including(dry_run: false, reason: 'promoted'))
      expect(output[:stdout]).to include('me***@example.com: member -> admin')
      expect(output[:stdout]).not_to include('Dry run')
    end

    it 'treats --yes as --apply' do
      run_cli_command_quietly('memberships', 'set-role', 'on_org_ext', 'ur_member', 'admin', '--yes')

      expect(set_role_op).to have_received(:new).with(hash_including(dry_run: false))
    end
  end
end
