# apps/api/organizations/spec/logic/organizations/delete_organization_spec.rb
#
# frozen_string_literal: true

# Regression coverage for the DeleteOrganization logic class after it was
# rewired onto the shared Onetime::Operations::Org::Delete op (#4204).
#
# Two things are being pinned here:
#
#   1. THE RESPONSE CONTRACT DID NOT MOVE. The teardown left this class, but
#      `{ user_id, deleted, extid }` is what the `organizationDelete` schema and
#      the workspace UI have always consumed.
#   2. THE SERVER NOW REFUSES WHAT ONLY VUE REFUSED BEFORE. `can_delete?` has
#      never had a caller, so a direct DELETE deleted an owner's default
#      workspace. The op's `:is_default` guardrail closes that, and this adapter
#      must NEVER pass a force flag that would reopen it.
#
# The teardown itself, the guardrails and the audit event belong to the op and
# are covered by spec/unit/onetime/operations/org/delete_spec.rb, so the op is
# stubbed at its constructor here.
#
# Run: pnpm run test:rspec apps/api/organizations/spec/logic/organizations/delete_organization_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'
require 'onetime/operations/org/delete'

RSpec.describe OrganizationAPI::Logic::Organizations::DeleteOrganization do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'owner@example.com',
      anonymous?: false,
      verified?: true,
      role: 'customer',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Org',
    )
  end

  let(:membership) do
    instance_double(Onetime::OrganizationMembership, active?: true, can?: true)
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: { 'csrf' => 'test-csrf-token' },
      user: customer,
      authenticated?: true,
      metadata: {})
  end

  let(:params) { { 'extid' => 'ext-org-123' } }
  let(:op) { instance_double(Onetime::Operations::Org::Delete) }
  let(:op_args) { [] }

  subject(:logic) { described_class.new(strategy_result, params) }

  def build_result(status:, **overrides)
    Onetime::Operations::Org::Delete::Result.new(
      **{
        status: status,
        org_id: 'ext-org-123',
        display_name: 'Test Org',
        planid: 'free_v1',
        members: [{ extid: 'ext-cust-123', email: 'owner@example.com' }],
        members_notified: 1,
        pending_invitations: 0,
        domain_count: 0,
        domains: [],
        drifted_domains: [],
        is_default: false,
        active_subscription: false,
        owner_id: 'ext-cust-123',
        owner_org_count: 2,
        default_org_cleared: [],
        dry_run: false,
      }.merge(overrides),
    )
  end

  def stub_op(status: :success, **overrides)
    allow(op).to receive(:call).and_return(build_result(status: status, **overrides))
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)

    allow(Onetime::Organization).to receive(:find_by_extid)
      .with('ext-org-123').and_return(organization)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org-123', 'cust-123').and_return(membership)

    allow(Onetime::Operations::Org::Delete).to receive(:new) do |args|
      op_args << args
      op
    end
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    stub_op
  end

  def run_logic
    logic.raise_concerns
    logic.process
  end

  describe 'response contract (unchanged by the rewire)' do
    it 'returns user_id / deleted / extid' do
      expect(run_logic).to eq(
        user_id: 'ext-cust-123',
        deleted: true,
        extid: 'ext-org-123',
      )
    end

    it 'still requires the extid param' do
      logic = described_class.new(strategy_result, { 'extid' => '' })

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
    end

    it 'still 404s an unknown organization' do
      allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(nil)

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'still gates on the manage_org entitlement' do
      allow(membership).to receive(:can?).with('manage_org').and_return(false)
      allow(organization).to receive(:planid).and_return('free_v1')

      # EntitlementRequired < Forbidden — the gate is unchanged by the rewire.
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
      expect(Onetime::Operations::Org::Delete).not_to have_received(:new)
    end
  end

  describe 'delegation' do
    it 'contains no teardown of its own — the op does all of it' do
      run_logic

      expect(op_args.last).to include(org: organization, dry_run: false)
      # The three the old inline teardown owned. If any of them reappears on
      # this class, the "one destroy path" has been broken again and the shell
      # is back to a `bin/console` recipe that corrupts Organization.instances.
      expect(described_class.instance_methods(false))
        .not_to include(:notify_members_deleted, :remove_members, :destroy_organization)
    end

    it 'attributes the delete to the acting customer, not a sentinel' do
      run_logic

      expect(op_args.last).to include(actor: 'ext-cust-123', deleted_by: 'owner@example.com')
    end

    it 'NEVER passes a force flag (those are operator surfaces only)' do
      run_logic

      expect(op_args.last[:force_default]).to be_nil
      expect(op_args.last[:force_subscription]).to be_nil
    end

    it 'never audits from the adapter (the op owns the single event)' do
      run_logic

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'guardrails the server now enforces' do
    it 'refuses a DEFAULT WORKSPACE — the gap can_delete? never closed' do
      stub_op(status: :is_default, is_default: true)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.error_key).to eq('api.organizations.errors.delete_is_default')
      end
    end

    it 'refuses an actively-billing org rather than stranding the subscription' do
      stub_op(status: :active_subscription, active_subscription: true)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.error_key).to eq('api.organizations.errors.delete_active_subscription')
      end
    end

    it 'refuses on domains with a form error instead of a raw Problem' do
      stub_op(status: :has_domains, domain_count: 1, domains: ['a.example.com'])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.error_key).to eq('api.organizations.errors.delete_has_domains')
        expect(err.args[:domains]).to eq('a.example.com')
      end
    end

    it 'refuses unrepairable domain drift with the support message, not "remove your domains"' do
      # The op already tried the self-heal; these stayed INVISIBLE in the
      # owner's domain list, so telling them to remove domains points at
      # nothing they can see.
      stub_op(status: :drifted_domains, drifted_domains: ['ghost.example.com'])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.error_key).to eq('api.organizations.errors.delete_drifted_domains')
        expect(err.args[:domains]).to eq('ghost.example.com')
      end
    end

    it "refuses to strand an account with no workspace at all" do
      stub_op(status: :last_org, owner_org_count: 1)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.error_key).to eq('api.organizations.errors.delete_last_org')
      end
    end

    it 'fails loudly on a status outside the adapter contract, never a 200' do
      stub_op(status: :landed_partial)
      logic.raise_concerns

      expect { logic.process }
        .to raise_error(Onetime::Problem, /Unexpected delete status: landed_partial/)
    end

    it 'treats a leaked :planned as a broken dry_run pin' do
      stub_op(status: :planned, dry_run: true)
      logic.raise_concerns

      expect { logic.process }
        .to raise_error(Onetime::Problem, /Unexpected delete status: planned/)
    end
  end
end
