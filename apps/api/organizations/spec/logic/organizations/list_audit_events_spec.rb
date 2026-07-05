# apps/api/organizations/spec/logic/organizations/list_audit_events_spec.rb
#
# frozen_string_literal: true

# Authorization and shape coverage for the audit-events endpoint (#3633).
#
# The trail's write-side fidelity (completeness, accuracy, isolation,
# containment) is covered in
# apps/api/v2/spec/models/organization_audit_trail_spec.rb. This spec pins
# the read side: only authenticated, active members whose membership grants
# the `audit_logs` entitlement can read a trail, and pagination inputs are
# clamped server-side.
#
# Run: pnpm run test:rspec apps/api/organizations/spec/logic/organizations/list_audit_events_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Organizations::ListAuditEvents do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'admin@example.com',
      anonymous?: false,
      verified?: true,
      role: 'customer',
      'role?': false
    )
  end

  let(:sample_events) do
    [
      { 'kind' => 'revealed', 'at' => 1_783_200_100.0, 'receipt' => 'rcpt2', 'secret' => 'scrt2' },
      { 'kind' => 'created',  'at' => 1_783_200_000.0, 'receipt' => 'rcpt1', 'secret' => 'scrt1' },
    ]
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      planid: 'identity_plus'
    )
  end

  let(:membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
      can?: true
    )
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {})
  end

  let(:params) { { 'extid' => 'ext-org-123' } }

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:le)

    allow(Onetime::Organization).to receive(:find_by_extid)
      .with('ext-org-123')
      .and_return(organization)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org-123', 'cust-123')
      .and_return(membership)
    allow(organization).to receive(:audit_events_page).and_return(sample_events)
    allow(organization).to receive(:audit_event_count).and_return(42)
  end

  describe 'authorization' do
    it 'requires the audit_logs entitlement, not mere membership' do
      logic.process_params
      expect(membership).to receive(:can?).with('audit_logs').and_return(true)

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'rejects members whose plan/role does not grant audit_logs' do
      allow(membership).to receive(:can?).with('audit_logs').and_return(false)

      logic.process_params
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
    end

    it 'rejects non-members' do
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .and_return(nil)

      logic.process_params
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'rejects inactive memberships' do
      allow(membership).to receive(:active?).and_return(false)

      logic.process_params
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'rejects anonymous callers before touching the organization' do
      allow(customer).to receive(:anonymous?).and_return(true)

      logic.process_params
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
      expect(Onetime::Organization).not_to have_received(:find_by_extid)
    end

    it 'raises not-found for an unknown organization' do
      allow(Onetime::Organization).to receive(:find_by_extid)
        .with('ext-org-123')
        .and_return(nil)

      logic.process_params
      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end
  end

  describe 'response shape' do
    it 'returns the page newest-first with count, total, and paging details' do
      logic.process_params
      logic.raise_concerns
      data = logic.process

      expect(data[:records]).to eq(sample_events)
      expect(data[:count]).to eq(2)
      expect(data[:total]).to eq(42)
      expect(data[:organization_id]).to eq('ext-org-123')
      expect(data[:user_id]).to eq('ext-cust-123')
      expect(data[:details]).to eq({ offset: 0, limit: 50 })
    end
  end

  describe 'pagination input handling' do
    it 'passes through sane values' do
      logic = described_class.new(strategy_result, params.merge('offset' => '10', 'limit' => '25'))
      logic.process_params

      expect(logic.offset).to eq(10)
      expect(logic.limit).to eq(25)
    end

    it 'clamps hostile values server-side' do
      logic = described_class.new(strategy_result, params.merge('offset' => '-50', 'limit' => '99999'))
      logic.process_params

      expect(logic.offset).to eq(0)
      expect(logic.limit).to eq(200)
    end

    it 'floors a zero/garbage limit to 1' do
      logic = described_class.new(strategy_result, params.merge('limit' => '0'))
      logic.process_params

      expect(logic.limit).to eq(1)
    end
  end
end
