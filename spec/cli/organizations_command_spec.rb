# spec/cli/organizations_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots organizations …` (aliases `organization` and
# `org`).
#
# Scoped to the operator-input contract the commands own: one parent with two
# aliases, the `list` --limit guard, `show` resolving every ORG form
# (Org::Shared#resolve_org: extid, objid, cus_, sub_, custom-domain hostname),
# members rendered by public id with their membership role and status, and the
# missing-org error. Models are doubles; the integrity checks themselves are
# covered by try/unit/cli/organizations/doctor_command_try.rb.
#
# NOTE for later PRs: append `describe` blocks to this file rather than
# creating a sibling spec, so the whole `organizations` surface stays here.
#
# Run: tests/lanes/run unit --only spec/cli/organizations_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/list_command'
require 'onetime/cli/org/show_command'
require 'onetime/cli/organizations_command'

RSpec.describe 'Organizations Command', type: :cli do
  let(:org_objid) { '0199d3c4-5b6a-7c8d-9e0f-a1b2c3d4e5f6' }

  let(:owner) do
    double('Customer', objid: 'cust-obj-owner', extid: 'ur_owner_ext', obscure_email: 'ow***@acme.example')
  end

  let(:member) do
    double('Customer', objid: 'cust-obj-member', extid: 'ur_member_ext', obscure_email: 'me***@acme.example')
  end

  let(:memberships) do
    [
      double('OrganizationMembership', customer_objid: 'cust-obj-owner', role: 'owner', status: 'active'),
      double('OrganizationMembership', customer_objid: 'cust-obj-member', role: 'admin', status: 'active'),
    ]
  end

  let(:domain) do
    double('CustomDomain', extid: 'cd_dom_ext', display_domain: 'secrets.acme.example', verification_state: 'resolving')
  end

  let(:organization) do
    double(
      'Organization',
      objid: org_objid,
      extid: 'on_org_ext',
      display_name: 'Acme',
      owner_id: 'cust-obj-owner',
      owner: owner,
      contact_email: 'billing@acme.example',
      is_default: false,
      archived?: false,
      planid: 'identity_plus_v1',
      stripe_customer_id: 'cus_ABC123',
      stripe_subscription_id: 'sub_ABC123',
      subscription_status: 'active',
      member_count: 2,
      domain_count: 1,
      pending_invitation_count: 0,
      list_members: [owner, member],
      list_domains: [domain],
    )
  end

  before do
    allow(Onetime::Organization).to receive_messages(
      find_by_extid: nil,
      load: nil,
      find_by_stripe_customer_id: nil,
      find_by_stripe_subscription_id: nil,
    )
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
    allow(Onetime::OrganizationMembership).to receive(:active_for_org).and_return(memberships)
  end

  describe 'one parent, two aliases' do
    it 'resolves `organizations`, `organization` and `org` to the same parent command' do
      %w[organizations organization org].each do |name|
        expect(Onetime::CLI.get([name]).command).to eq(Onetime::CLI::OrganizationsCommand)
      end
    end

    it 'resolves a subcommand through either alias' do
      expect(Onetime::CLI.get(%w[org doctor]).command).to eq(Onetime::CLI::OrgDoctorCommand)
      expect(Onetime::CLI.get(%w[organization show]).command).to eq(Onetime::CLI::OrgShowCommand)
      expect(Onetime::CLI.get(%w[organizations list]).command).to eq(Onetime::CLI::OrgListCommand)
    end

    it 'prints usage under the canonical name' do
      allow(Onetime::Organization).to receive(:instances).and_return(double('Instances', size: 3))

      output = run_cli_command_quietly('org')

      expect(output[:stdout]).to include('3 organizations')
      expect(output[:stdout]).to include('bin/ots organizations show ORG')
      expect(output[:stdout]).to include('bin/ots organizations list')
      expect(output[:stdout]).to include('7. display_name is not blank')
    end

    it 'has no add-member verb (`memberships add` covers it)' do
      # dry-cli stops at the deepest registered node: `add-member` is left as
      # an argument to the parent rather than resolving to a command.
      expect(Onetime::CLI.get(%w[organizations add-member]).names).to eq(['organizations'])
    end
  end

  describe 'list' do
    describe '--limit validation' do
      it 'rejects a negative --limit instead of crashing on take(-1)' do
        output = run_cli_command_quietly('organizations', 'list', '--limit', '-1')
        expect(output[:stdout]).to include('--limit must be a positive integer')
        expect(last_exit_code).to eq(1)
      end

      it 'rejects a zero --limit rather than listing nothing' do
        output = run_cli_command_quietly('organizations', 'list', '--limit', '0')
        expect(output[:stdout]).to include('--limit must be a positive integer')
        expect(last_exit_code).to eq(1)
      end
    end

    it 'lists by extid, and members by extid with role under --verbose' do
      allow(Onetime::Organization).to receive(:instances).and_return(double('Instances', all: [org_objid]))
      allow(Onetime::Organization).to receive(:load).with(org_objid).and_return(organization)

      output = run_cli_command_quietly('org', 'list', '--verbose')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('1 total organizations')
      expect(output[:stdout]).to include('on_org_ext')
      expect(output[:stdout]).to match(/member: ur_member_ext\s+admin\s+active\s+me\*\*\*@acme\.example/)
      expect(output[:stdout]).not_to include('cust-obj-member')
    end

    it 'emits JSON with --json' do
      allow(Onetime::Organization).to receive(:instances).and_return(double('Instances', all: [org_objid]))
      allow(Onetime::Organization).to receive(:load).with(org_objid).and_return(organization)

      payload = JSON.parse(run_cli_command_quietly('organizations', 'list', '--json')[:stdout])

      expect(payload['total']).to eq(1)
      expect(payload['organizations'].first).to include('extid' => 'on_org_ext', 'planid' => 'identity_plus_v1')
    end
  end

  describe 'show' do
    it 'resolves by extid' do
      output = run_cli_command_quietly('organizations', 'show', 'on_org_ext')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Organization: Acme')
    end

    it 'resolves by objid when the extid lookup misses' do
      allow(Onetime::Organization).to receive(:load).with(org_objid).and_return(organization)

      output = run_cli_command_quietly('organizations', 'show', org_objid)

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('on_org_ext')
    end

    it 'resolves a cus_ id through the Stripe customer index only' do
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).with('cus_ABC123').and_return(organization)

      run_cli_command_quietly('organizations', 'show', 'cus_ABC123')

      expect(last_exit_code).to eq(0)
      expect(Onetime::Organization).not_to have_received(:find_by_extid)
      expect(Onetime::Organization).not_to have_received(:load)
    end

    it 'resolves a sub_ id through the Stripe subscription index' do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id).with('sub_ABC123').and_return(organization)

      output = run_cli_command_quietly('organizations', 'show', 'sub_ABC123')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Organization: Acme')
    end

    it "resolves a custom-domain hostname to the domain's primary organization" do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('secrets.acme.example').and_return(double('CustomDomain', primary_organization: organization))

      output = run_cli_command_quietly('organizations', 'show', 'secrets.acme.example')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Organization: Acme')
    end

    it 'renders members as extid / role / status / obscured email, never objids' do
      output = run_cli_command_quietly('organizations', 'show', 'on_org_ext')

      expect(output[:stdout]).to match(/ur_owner_ext\s+owner\s+active\s+ow\*\*\*@acme\.example/)
      expect(output[:stdout]).to match(/ur_member_ext\s+admin\s+active\s+me\*\*\*@acme\.example/)
      expect(output[:stdout]).not_to include('cust-obj-owner')
      expect(output[:stdout]).not_to include('cust-obj-member')
      expect(output[:stdout]).not_to include('billing@acme.example')
      expect(output[:stdout]).to include('secrets.acme.example  (state: resolving)')
    end

    it 'flags members-set entries that have no customer record' do
      allow(organization).to receive(:member_count).and_return(3)

      output = run_cli_command_quietly('organizations', 'show', 'on_org_ext')

      expect(output[:stdout]).to include('+1 member entry with no customer record')
    end

    it 'emits members by public id in --json' do
      payload = JSON.parse(run_cli_command_quietly('organizations', 'show', 'on_org_ext', '--json')[:stdout])

      expect(payload['extid']).to eq('on_org_ext')
      expect(payload['owner']).to eq('extid' => 'ur_owner_ext', 'email' => 'ow***@acme.example')
      expect(payload['members'].map { |m| m.values_at('extid', 'role', 'status') })
        .to eq([%w[ur_owner_ext owner active], %w[ur_member_ext admin active]])
      expect(payload['billing']['stripe_customer_id']).to eq('cus_ABC123')
    end

    it 'exits 1 with the shared error when the organization cannot be resolved' do
      output = run_cli_command_quietly('organizations', 'show', 'on_missing')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_missing')
    end

    it 'exits 1 with a JSON error for an unknown cus_ id in --json mode' do
      output = run_cli_command_quietly('organizations', 'show', 'cus_nope', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to eq('error' => 'Organization not found: cus_nope')
    end
  end
end
