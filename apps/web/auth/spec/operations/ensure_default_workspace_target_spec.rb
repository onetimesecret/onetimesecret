# apps/web/auth/spec/operations/ensure_default_workspace_target_spec.rb
#
# frozen_string_literal: true

# Which organization EnsureDefaultWorkspace hands back when it did not create
# one, on the shared lookup fixture (another owner's default listed first, the
# customer's archived default second, their live owned default third):
#
#   claim_pending_federation      — the deferred claim writes a plan onto the
#                                   target, so it is the owned default
#                                   workspace (#signup_workspace_for) or none.
#   await_concurrent_provisioning — the lock holder's workspace: the owned
#                                   default, else the first owned org.
#
# The old shared lookup stopped at the first is_default flag, then fell to
# the first membership — a joined organization either way. The lock and
# collision behaviour is covered by ensure_default_workspace_collision_spec.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/ensure_default_workspace_target_spec.rb
require 'spec_helper'
require 'auth/operations/ensure_default_workspace'

RSpec.describe Auth::Operations::EnsureDefaultWorkspace do
  include_context 'default workspace lookup fixture'

  let(:memberships) { lookup_fixture_orgs }
  let(:organizations) { double('organization_instances', count: memberships.size, to_a: memberships) }
  let(:customer) do
    double(
      'Customer',
      email: 'target@example.com',
      custid: 'cust_target',
      objid: 'cust_target',
      extid: 'ur_target',
      anonymous?: false,
      default_org_id: '',
      verified?: true,
      organization_instances: organizations,
      clear_provisioning_failure!: false,
    )
  end
  let(:owned_team) do
    instance_double(
      Onetime::Organization,
      objid: 'org-owned-team',
      extid: 'or_owned_team',
      display_name: 'Team',
      is_default: false,
      archived?: false,
    )
  end

  before do
    stub_workspace_ownership(customer)
    allow(owned_team).to receive(:owner?).with(customer).and_return(true)
  end

  describe '#claim_pending_federation' do
    let(:operation) do
      described_class.new(customer: customer).tap do |op|
        allow(op).to receive(:apply_pending_federation!).and_return(true)
      end
    end

    it 'claims onto the owned default workspace, not the foreign default listed first' do
      expect(operation.claim_pending_federation).to be(true)
      expect(operation).to have_received(:apply_pending_federation!).with(owned_default)
    end

    context 'when the customer owns no live default workspace' do
      let(:memberships) { [foreign_default, archived_default, owned_team] }

      it 'leaves the pending record unclaimed rather than claim onto a joined or non-default org' do
        expect(operation.claim_pending_federation).to be(false)
        expect(operation).not_to have_received(:apply_pending_federation!)
      end
    end
  end

  describe 'the result of concurrent provisioning' do
    let(:lock) { instance_double(Familia::Lock, acquire: false) }
    let(:operation) { described_class.new(customer: customer) }

    before do
      allow(Familia::Lock).to receive(:new).and_return(lock)
      stub_const('Auth::Operations::EnsureDefaultWorkspace::CREATE_LOCK_WAIT', 0.2)
      stub_const('Auth::Operations::EnsureDefaultWorkspace::CREATE_LOCK_INTERVAL', 0.01)
      # No org on the first check, then the holder's workspace appears.
      allow(organizations).to receive(:count).and_return(0, memberships.size)
    end

    it 'returns the owned default workspace, not the foreign default listed first' do
      expect(operation.call).to eq(organization: owned_default)
    end

    context 'when the holder was CreateOrganization (an owned, non-default org)' do
      let(:memberships) { [foreign_default, owned_team] }

      it 'returns the first owned organization' do
        expect(operation.call).to eq(organization: owned_team)
      end
    end

    context 'when only a joined organization appeared' do
      let(:memberships) { [foreign_default] }

      it 'returns no organization, as the holder itself would' do
        expect(operation.call).to eq(organization: nil)
      end
    end
  end
end
