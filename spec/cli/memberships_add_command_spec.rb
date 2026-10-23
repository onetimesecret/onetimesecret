# spec/cli/memberships_add_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots memberships add ORG CUSTOMER`.
#
# Covers the ORG grammar shared with `organizations …` (an org objid resolves,
# not only an extid) and `--default`, which asks SetDefaultOrganization to make
# ORG the customer's default once they are an active member of it. Both
# mutations are their ops' job (spec/unit/onetime/operations/memberships/
# add_spec.rb and the SetDefaultOrganization op spec); here both ops are
# stubbed at their constructors so these stay pure adapter tests.
#
# Run: tests/lanes/run unit --only spec/cli/memberships_add_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/memberships/shared'
require 'onetime/cli/memberships/add_command'

RSpec.describe 'Memberships Add Command', type: :cli do
  let(:org_objid) { '0199d3c4-5b6a-7c8d-9e0f-a1b2c3d4e5f6' }
  let(:archived) { false }

  let(:organization) do
    double('Organization', objid: org_objid, extid: 'on_org_ext', display_name: 'Acme', archived?: archived)
  end

  let(:member) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member', obscure_email: 'me***@example.com', anonymous?: false)
  end

  let(:status) { :success }

  let(:result) do
    Onetime::Operations::Memberships::Add::Result.new(
      status: status, org_id: 'on_org_ext', customer_id: 'ur_member', role: 'member',
    )
  end

  let(:operation) { instance_double(Onetime::Operations::Memberships::Add, call: result) }

  let(:default_status) { :success }

  let(:default_operation) do
    instance_double(
      Onetime::Operations::Customers::SetDefaultOrganization,
      call: Onetime::Operations::Customers::SetDefaultOrganization::Result.new(
        status: default_status, customer: member, organization: organization, previous: nil, dry_run: false,
      ),
    )
  end

  before do
    allow(Onetime::Organization).to receive_messages(find_by_extid: nil, load: nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_member').and_return(member)
    allow(Onetime::Operations::Memberships::Add).to receive(:new).and_return(operation)
    allow(Onetime::Operations::Customers::SetDefaultOrganization).to receive(:new).and_return(default_operation)
  end

  describe 'ORG resolution' do
    it 'accepts an org objid (extid lookup misses, objid load hits)' do
      allow(Onetime::Organization).to receive(:load).with(org_objid).and_return(organization)

      run_cli_command_quietly('memberships', 'add', org_objid, 'ur_member', '--yes')

      expect(last_exit_code).to eq(0)
      expect(Onetime::Operations::Memberships::Add).to have_received(:new).with(hash_including(org: organization))
    end

    it 'exits 1 without calling the op when ORG resolves to nothing' do
      output = run_cli_command_quietly('memberships', 'add', 'on_missing', 'ur_member', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_missing')
      expect(Onetime::Operations::Memberships::Add).not_to have_received(:new)
    end
  end

  describe '--default' do
    let(:set_default) { Onetime::Operations::Customers::SetDefaultOrganization }

    it 'asks SetDefaultOrganization for ORG after a fresh add, as the CLI actor' do
      output = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default', '--yes')

      expect(last_exit_code).to eq(0)
      expect(set_default).to have_received(:new).with(customer: member, organization: organization, actor: 'cli')
      expect(output[:stdout]).to include('Default organization for me***@example.com: on_org_ext')
    end

    context 'when the customer is already a member' do
      let(:status) { :no_change }

      it 'still sets the default (the member is active in ORG)' do
        run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default', '--yes')

        expect(set_default).to have_received(:new)
      end
    end

    context 'when ORG already is their default' do
      let(:default_status) { :no_change }

      it 'reports the default and exits 0' do
        output = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default', '--yes')

        expect(last_exit_code).to eq(0)
        expect(output[:stdout]).to include('Default organization for me***@example.com: on_org_ext')
      end
    end

    it 'leaves the default alone without --default' do
      run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--yes')

      expect(set_default).not_to have_received(:new)
    end

    context 'when the add op refuses the role' do
      let(:status) { :invalid_role }

      it 'does not attempt the default and exits 1' do
        run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--role', 'boss', '--default', '--yes')

        expect(last_exit_code).to eq(1)
        expect(set_default).not_to have_received(:new)
      end
    end

    context 'when SetDefaultOrganization refuses' do
      let(:default_status) { :not_member }

      it 'exits 1 and names the refusal' do
        output = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default', '--yes')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('Default organization not changed (not_member)')
      end
    end

    context 'when ORG is archived' do
      let(:archived) { true }

      it 'refuses before adding anything' do
        output = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default', '--yes')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include('Cannot make archived organization on_org_ext a default')
        expect(Onetime::Operations::Memberships::Add).not_to have_received(:new)
      end
    end

    it 'mentions the default in the confirmation prompt, and a decline writes nothing' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default')

      expect(output[:stdout]).to include('and make it their default organization? [y/N]')
      expect(Onetime::Operations::Memberships::Add).not_to have_received(:new)
      expect(set_default).not_to have_received(:new)
    end

    it 'reports default_org_status in --json' do
      output  = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--default', '--yes', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload).to include('status' => 'success', 'member_id' => 'ur_member', 'default_org_status' => 'success')
    end

    it 'omits default_org_status in --json without --default' do
      output  = run_cli_command_quietly('memberships', 'add', 'on_org_ext', 'ur_member', '--yes', '--json')

      expect(JSON.parse(output[:stdout])).not_to have_key('default_org_status')
    end
  end
end
