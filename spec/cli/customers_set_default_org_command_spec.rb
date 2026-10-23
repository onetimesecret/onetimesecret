# spec/cli/customers_set_default_org_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots customers set-default-org CUSTOMER ORG`.
#
# Covers customer + org resolution, the --yes / --json refusal, the interactive
# decline, the CLI actor sentinel, --dry-run, and the op-status -> output /
# exit-code mapping. The membership / archived rule, the write and the audit
# event are the op's job and are covered by
# spec/unit/onetime/operations/customers/set_default_organization_spec.rb — here
# the op is stubbed at its constructor so these stay pure adapter tests.
#
# Run: tests/lanes/run unit --only spec/cli/customers_set_default_org_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; also listed in the lib/onetime/cli.rb
# manifest. Required here so the spec is independent of manifest ordering.
require 'onetime/cli/customers/set_default_org_command'

RSpec.describe 'Customers Set Default Org Command', type: :cli do
  let(:op_class) { Onetime::Operations::Customers::SetDefaultOrganization }

  let(:team) { double('Organization', objid: 'org-team-obj', extid: 'on_team', display_name: 'Team') }
  let(:home) { double('Organization', objid: 'org-home-obj', extid: 'on_home', display_name: 'Home') }

  let(:member) do
    double(
      'Customer',
      objid: 'cust-obj-1',
      extid: 'ur_member',
      obscure_email: 'me*****@example.com',
      anonymous?: false,
    )
  end

  def op_result(status, previous: home, dry_run: false)
    op_class::Result.new(status: status, customer: member, organization: team, previous: previous, dry_run: dry_run)
  end

  def stub_op(status, **)
    allow(op_class).to receive(:new).and_return(instance_double(op_class, call: op_result(status, **)))
  end

  def run(*args)
    run_cli_command_quietly('customers', 'set-default-org', *args)
  end

  before do
    allow(Onetime::Organization).to receive_messages(find_by_extid: nil, load: nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_team').and_return(team)
    allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_member').and_return(member)
    stub_op(:success)
  end

  describe 'resolution' do
    it 'exits 1 when the customer cannot be resolved' do
      output = run('ghost', 'on_team', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Customer not found: ghost')
      expect(op_class).not_to have_received(:new)
    end

    it 'exits 1 when the organization cannot be resolved' do
      output = run('ur_member', 'on_ghost', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_ghost')
      expect(op_class).not_to have_received(:new)
    end

    it 'refuses an anonymous customer' do
      allow(member).to receive(:anonymous?).and_return(true)

      output = run('ur_member', 'on_team', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('anonymous customer')
      expect(op_class).not_to have_received(:new)
    end
  end

  describe 'confirmation' do
    it 'refuses to apply without --yes in --json mode' do
      output = run('ur_member', 'on_team', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['error'])
        .to eq('Refusing to change the default organization without --yes in --json mode')
      expect(op_class).not_to have_received(:new)
    end

    it 'aborts without calling the op when the prompt is declined' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run('ur_member', 'on_team')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Aborted.')
      expect(op_class).not_to have_received(:new)
    end

    it 'applies after an interactive confirmation' do
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run('ur_member', 'on_team')

      expect(output[:stdout]).to include('Set the default organization of me*****@example.com to on_team?')
      expect(op_class).to have_received(:new)
    end
  end

  describe 'the op call' do
    it 'passes the CLI actor sentinel, never a Customer, and the reason' do
      run('ur_member', 'on_team', '--yes', '--reason', 'ticket 42')

      expect(op_class).to have_received(:new).with(
        customer: member,
        organization: team,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        reason: 'ticket 42',
        dry_run: false,
      )
    end

    it 'runs --dry-run without a confirmation prompt' do
      stub_op(:dry_run, dry_run: true)
      allow($stdin).to receive(:gets)

      output = run('ur_member', 'on_team', '--dry-run')

      expect(last_exit_code).to eq(0)
      expect($stdin).not_to have_received(:gets)
      expect(op_class).to have_received(:new).with(hash_including(dry_run: true))
      expect(output[:stdout]).to include('would set default organization on_home -> on_team (dry run, nothing written)')
    end
  end

  describe 'output' do
    it 'reports the previous and new default on success' do
      output = run('ur_member', 'on_team', '--yes')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('me*****@example.com: default organization on_home -> on_team')
    end

    it 'reports (none) when there was no previous default' do
      stub_op(:success, previous: nil)

      output = run('ur_member', 'on_team', '--yes')

      expect(output[:stdout]).to include('default organization (none) -> on_team')
    end

    it 'reports a no-op and exits 0 when it was already the default' do
      stub_op(:no_change, previous: team)

      output = run('ur_member', 'on_team', '--yes')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('on_team is already the default organization')
    end

    it 'exits 1 for a non-member organization' do
      stub_op(:not_member, previous: nil)

      output = run('ur_member', 'on_team', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: me*****@example.com is not an active member of on_team')
    end

    it 'exits 1 for an archived organization' do
      stub_op(:archived, previous: nil)

      output = run('ur_member', 'on_team', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: on_team is archived')
    end

    it 'emits the result as JSON and exits 0 on --yes --json' do
      output = run('ur_member', 'on_team', '--yes', '--json')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])).to eq(
        'status' => 'success',
        'customer_id' => 'ur_member',
        'email' => 'me*****@example.com',
        'default_organization' => 'on_team',
        'previous_default_organization' => 'on_home',
        'dry_run' => false,
      )
    end

    it 'emits a refusal as JSON and exits 1' do
      stub_op(:not_member, previous: nil)

      output = run('ur_member', 'on_team', '--yes', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['status']).to eq('not_member')
    end
  end
end
