# spec/cli/memberships_remove_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots memberships remove ORG CUSTOMER`.
#
# Covers the dry-run default (nothing written without --apply, no prompt) and
# the op-status -> exit-code mapping. The removal and its audit events are the
# op's job (spec/unit/onetime/operations/memberships/remove_spec.rb); here the
# op is stubbed at its constructor so these stay pure adapter tests.
#
# Run: tests/lanes/run unit --only spec/cli/memberships_remove_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/memberships/shared'
require 'onetime/cli/memberships/remove_command'

RSpec.describe 'Memberships Remove Command', type: :cli do
  let(:organization) do
    double('Organization', objid: 'org-obj-1', extid: 'on_org_ext', display_name: 'Acme')
  end

  let(:member) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member', obscure_email: 'me***@example.com', anonymous?: false)
  end

  let(:status) { :dry_run }

  let(:result) do
    Onetime::Operations::Memberships::Remove::Result.new(
      status: status, org_id: 'on_org_ext', customer_id: 'ur_member', role: 'admin',
    )
  end

  let(:remove_op) { Onetime::Operations::Memberships::Remove }

  before do
    allow(Onetime::Organization).to receive_messages(find_by_extid: nil, load: nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_member').and_return(member)
    allow(remove_op).to receive(:new).and_return(instance_double(remove_op, call: result))
  end

  describe 'dry run (the default)' do
    it 'asks the op for a dry run without --apply, never prompting' do
      allow($stdin).to receive(:gets)

      output = run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member')

      expect(last_exit_code).to eq(0)
      expect(remove_op).to have_received(:new).with(
        org: organization,
        customer: member,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        reason: nil,
        dry_run: true,
      )
      expect($stdin).not_to have_received(:gets)
      expect(output[:stdout]).to include('DRY RUN — nothing was written')
      expect(output[:stdout]).to include('Would remove me***@example.com (role: admin) from on_org_ext')
      expect(output[:stdout]).to include('Re-run with --apply to remove.')
    end

    it 'emits dry_run: true in --json and exits 0' do
      output = run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member', '--json')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])).to include('status' => 'dry_run', 'dry_run' => true, 'role' => 'admin')
    end

    it 'refuses --apply with --dry-run before calling the op' do
      output = run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member', '--apply', '--dry-run')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('--apply and --dry-run are contradictory')
      expect(remove_op).not_to have_received(:new)
    end

    context 'when the member is the last owner' do
      let(:status) { :last_owner }

      it 'exits 1 on the dry run too' do
        output = run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('Cannot remove the last remaining owner')
      end
    end
  end

  describe 'with --apply' do
    let(:status) { :success }

    it 'asks the op to write and threads --reason through' do
      output = run_cli_command_quietly(
        'memberships', 'remove', 'on_org_ext', 'ur_member', '--apply', '--reason', 'left the company'
      )

      expect(last_exit_code).to eq(0)
      expect(remove_op).to have_received(:new).with(hash_including(dry_run: false, reason: 'left the company'))
      expect(output[:stdout]).to include('Removed me***@example.com from on_org_ext')
    end

    it 'treats --yes and -y as --apply' do
      run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member', '--yes')
      run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member', '-y')

      expect(remove_op).to have_received(:new).with(hash_including(dry_run: false)).twice
    end

    context 'when the customer is not a member' do
      let(:status) { :not_found }

      it 'exits 1 with the status in --json' do
        output = run_cli_command_quietly('memberships', 'remove', 'on_org_ext', 'ur_member', '--apply', '--json')

        expect(last_exit_code).to eq(1)
        expect(JSON.parse(output[:stdout])).to include('status' => 'not_found', 'dry_run' => false)
      end
    end
  end
end
