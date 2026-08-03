# apps/api/organizations/spec/logic/organizations/list_secret_activity_spec.rb
#
# frozen_string_literal: true

# Authorization and shape coverage for the secret-activity endpoint (#3633).
#
# The trail's write-side fidelity (completeness, accuracy, isolation,
# containment) is covered in
# apps/api/v2/spec/models/organization_secret_activity_spec.rb. This spec pins
# the read side: only authenticated, active members whose membership grants
# the `audit_logs` entitlement can read a trail, and pagination inputs are
# clamped server-side.
#
# Run: pnpm run test:rspec apps/api/organizations/spec/logic/organizations/list_secret_activity_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Organizations::ListSecretActivity do
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

  # Full actor objids (never truncated in the trail — NIST AU-3/PCI 10.2.2).
  # 'cust-gone-456' models a since-removed member: its objid stays in the
  # trail but no longer resolves through the org-membership join.
  let(:sample_events) do
    [
      { 'kind' => 'revealed', 'at' => 1_783_200_100.0, 'receipt' => 'rcpt2', 'secret' => 'scrt2',
        'actor_id' => 'cust-actor-789' },
      { 'kind' => 'created',  'at' => 1_783_200_000.0, 'receipt' => 'rcpt1', 'secret' => 'scrt1',
        'actor_id' => 'cust-gone-456' },
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

  let(:actor_customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-actor-789',
      extid: 'ext-cust-actor-789',
      email: 'actor@example.com'
    )
  end

  let(:actor_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
      customer: actor_customer
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
    # Unknown/removed actors (e.g. 'cust-gone-456') fall through to nil.
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .and_return(nil)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org-123', 'cust-123')
      .and_return(membership)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org-123', 'cust-actor-789')
      .and_return(actor_membership)
    allow(organization).to receive(:secret_activity_events_page).and_return(sample_events)
    allow(organization).to receive(:secret_activity_event_count).and_return(42)
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

  # Instance-level exclusion (ORGS_AUDIT_LOGS_ENABLED). Default-true contract:
  # only an explicit false disables — an absent key (older config file) must
  # count as enabled. The check gates exposure only; SecretActivity collection
  # is out of scope here.
  describe 'instance feature flag' do
    def conf_with_audit_logs_flag(orgs_features)
      base     = OT.conf
      features = (base['features'] || {}).merge('organizations' => orgs_features)
      base.merge('features' => features)
    end

    it 'rejects with forbidden before loading the org when the flag is false' do
      allow(OT).to receive(:conf)
        .and_return(conf_with_audit_logs_flag('audit_logs_enabled' => false))

      logic.process_params
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) { |ex|
        expect(ex.error_type).to eq(:forbidden)
      }
      expect(Onetime::Organization).not_to have_received(:find_by_extid)
    end

    it 'proceeds when the flag is explicitly true' do
      allow(OT).to receive(:conf)
        .and_return(conf_with_audit_logs_flag('audit_logs_enabled' => true))

      logic.process_params
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'counts an absent key as enabled (default-true contract)' do
      allow(OT).to receive(:conf).and_return(conf_with_audit_logs_flag({}))

      logic.process_params
      expect { logic.raise_concerns }.not_to raise_error
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
      expect(data[:details]).to eq({
        offset: 0,
        limit: 50,
        actors: { 'cust-actor-789' => { 'email' => 'actor@example.com', 'extid' => 'ext-cust-actor-789' } },
      })
    end
  end

  describe 'actor resolution' do
    before do
      logic.process_params
      logic.raise_concerns
    end

    it 'resolves active members to email + extid, keyed by full objid' do
      data = logic.process

      expect(data[:details][:actors]).to eq(
        'cust-actor-789' => { 'email' => 'actor@example.com', 'extid' => 'ext-cust-actor-789' },
      )
    end

    it 'omits removed/unknown actors so the UI renders the bare objid' do
      data = logic.process

      expect(data[:details][:actors]).not_to have_key('cust-gone-456')
    end

    it 'never mutates events — actor_id stays the raw full objid' do
      data = logic.process

      expect(data[:records].map { |ev| ev['actor_id'] }).to eq(%w[cust-actor-789 cust-gone-456])
      expect(data[:records].none? { |ev| ev.key?('email') }).to be(true)
    end

    it 'excludes actors whose membership is no longer active' do
      allow(actor_membership).to receive(:active?).and_return(false)

      data = logic.process

      expect(data[:details][:actors]).to eq({})
    end

    it 'skips an actor whose resolution raises instead of failing the page' do
      allow(actor_membership).to receive(:customer).and_raise(StandardError, 'redis hiccup')

      data = logic.process

      expect(data[:details][:actors]).to eq({})
      expect(OT).to have_received(:le).with(/actor resolution failed/, hash_including(actor_id: 'cust-actor-789'))
    end

    it 'leaves events without an actor_id out of the lookup entirely' do
      allow(organization).to receive(:secret_activity_events_page).and_return([
        { 'kind' => 'expired', 'at' => 1_783_200_200.0, 'receipt' => 'rcpt3', 'secret' => 'scrt3' },
      ])

      data = logic.process

      expect(data[:details][:actors]).to eq({})
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
