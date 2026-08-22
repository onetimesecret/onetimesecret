# apps/api/colonel/spec/logic/colonel/get_organization_detail_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# Narrow coverage for one property of the detail payload's `record` hash. The
# rest of it (entitlement drift, roster, domains) is not exercised here — those
# builders are stubbed so each example is about one field.
#
# A pseudonymous diagnostics reference is published as `organization_ref`, keyed
# by Onetime::Utils::DiagnosticsRef. The current frontend contract discards it,
# so it is not attached to Sentry and organization correlation is not active.
#
# The examples below pin the response contract: the ref is opaque and derived,
# is not the objid or extid it comes from, and leaves the identifiers an operator
# legitimately reads on this authenticated Colonel response unchanged.
#
# Run with:
#   tests/lanes/run unit --only apps/api/colonel/spec/logic/colonel/get_organization_detail_spec.rb
RSpec.describe ColonelAPI::Logic::Colonel::GetOrganizationDetail do
  let(:objid) { '01JORGABCDEFGHJKMNPQRSTVWX' }
  let(:extid) { 'on1234567890s' }
  let(:period_end) { nil }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:org) do
    instance_double(Onetime::Organization,
      objid: objid, extid: extid, exists?: true,
      display_name: 'Target Org', description: nil,
      is_default: false, archived?: false, archived_at: nil, archived_comment: nil,
      contact_email: 'contact@example.com', owner_id: 'cust_owner',
      billing_email: 'billing@example.com',
      member_count: 3, domain_count: 1,
      created: 1_700_000_000, updated: 1_700_000_001,
      planid: 'free_v1', stripe_customer_id: nil, stripe_subscription_id: nil,
      subscription_status: nil, subscription_period_end: period_end)
  end

  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: {})
  end

  let(:logic) do
    described_class.new(strategy_result, { 'org_id' => extid }).tap do |instance|
      instance.instance_variable_set(:@org, org)
      allow(instance).to receive_messages(
        owner: nil,
        build_entitlements: {},
        build_available_entitlements: [],
        build_members: [],
        build_domains: [],
      )
    end
  end

  let(:record) { logic.send(:success_data)[:record] }

  before do
    allow(Billing::BillingService).to receive_messages(
      compute_sync_status: 'ok',
      compute_sync_status_reason: nil,
    )
  end

  describe 'diagnostics references' do
    # Pin a known keying rather than inheriting whatever the lane exports.
    # DiagnosticsRef refuses the shared federation secret when no residency
    # resolves, so an unpinned lane could make every example here assert
    # against nil and pass for the wrong reason.
    let(:keying) do
      Onetime::Utils::DiagnosticsRef::Keying.new(
        secret: 'a-known-diagnostics-key', scope: 'federated', residency: 'stub-region'
      )
    end

    before { allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(keying) }

    it 'publishes an opaque organization ref, 16 lowercase hex chars' do
      expect(record[:organization_ref]).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'derives the ref from the objid without disclosing objid or extid' do
      expect(record[:organization_ref])
        .to eq(Onetime::Utils::DiagnosticsRef.organization_ref(objid))

      expect(record[:organization_ref]).not_to eq(objid)
      expect(record[:organization_ref]).not_to eq(extid)
      expect(objid.downcase).not_to include(record[:organization_ref])
      expect(extid.downcase).not_to include(record[:organization_ref])
    end

    it 'distinguishes one organization from another' do
      other = Onetime::Utils::DiagnosticsRef.organization_ref('01JOTHERABCDEFGHJKMNPQRSTVW')

      expect(other).to match(/\A[0-9a-f]{16}\z/)
      expect(record[:organization_ref]).not_to eq(other)
    end

    it 'is domain separated from the user namespace' do
      # A pre-image both entry points treat identically — already lowercase,
      # unpadded, NFC — so the only difference left is the purpose prefix.
      probe = 'domain-separation-probe'

      expect(Onetime::Utils::DiagnosticsRef.organization_ref(probe))
        .not_to eq(Onetime::Utils::DiagnosticsRef.actor_ref(probe))
    end

    it 'still returns the identifiers an operator actually looks up' do
      expect(record[:org_id]).to eq(objid)
      expect(record[:extid]).to eq(extid)
    end

    it 'publishes no OTHER diagnostics-restricted identifier as a ref' do
      # Everything the privacy rules forbid on the diagnostics surface stays a
      # plain operator field on this authenticated response and gains no
      # pseudonymous twin.
      %i[extid_ref display_name_ref owner_ref owner_email_ref billing_email_ref
         contact_email_ref stripe_customer_ref].each do |field|
        expect(record).not_to have_key(field)
      end
    end

    context 'when the deployment has no usable keying secret' do
      let(:keying) { nil }

      it 'keeps the key present and the value null' do
        expect(record).to have_key(:organization_ref)
        expect(record[:organization_ref]).to be_nil
      end
    end
  end
end
