# apps/api/v2/spec/logic/secrets/receipt_activity_audit_parity_spec.rb
#
# frozen_string_literal: true

# AUDIT-GATE PARITY between the two org-wide "who read what" surfaces:
#
#   - V2::Logic::Secrets::ListReceipts (scope: :org)
#   - OrganizationAPI::Logic::Organizations::ListSecretActivity
#
# #4196's follow-up commit fixed a real drift (#4213): a ListReceipts comment
# claimed the two "cannot disagree" about ORGS_AUDIT_LOGS_ENABLED, but the
# kill switch only reached ListSecretActivity — an operator who disabled the
# feature still had the receipt stream reachable via ListReceipts. A prose
# comment restating the claim is not what would have caught that regression;
# this spec is. It drives both logic classes from the SAME toggled inputs
# (instance flag on/off, audit_logs entitlement granted/withheld) and asserts
# their allow/deny verdicts AGREE, rather than asserting each independently
# against a table of expected outcomes — the same style as
# apps/web/core/spec/views/serializers/restrict_to_parity_spec.rb.
#
# Only scope: :org is driven here. scope: :domain reuses the identical
# audit_logs_enabled check (see list_receipts.rb's AUDIT_SURFACE_SCOPES) and
# already has its own dedicated coverage in list_receipts_authorization_spec.rb.
#
# Run: bundle exec rspec apps/api/v2/spec/logic/secrets/receipt_activity_audit_parity_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'v2/logic'
require 'organizations/logic'

RSpec.describe 'ListReceipts(scope: :org) / ListSecretActivity audit-gate parity' do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-parity-123',
      custid: 'cust-parity-123',
      extid: 'ext-cust-parity-123',
      email: 'admin@example.com',
      anonymous?: false,
      verified?: true,
      role: 'customer',
      role?: false,
      planid: 'identity_plus_v1',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-parity-123',
      extid: 'ext-org-parity-123',
      planid: 'identity_plus_v1',
    )
  end

  let(:session) do
    double('Session', anonymous?: false, custid: 'cust-parity-123', identifier: 'sess-parity-123')
  end

  # Both logic classes only read session/user/metadata from strategy_result,
  # so one double serves both — matching the shape each surface's own spec
  # already uses (list_receipts_authorization_spec.rb,
  # list_secret_activity_spec.rb).
  let(:strategy_result) do
    double(
      'StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: { organization_context: {} },
    )
  end

  before(:all) { OT.boot!(:test) }

  # Override features.organizations.audit_logs_enabled without disturbing the
  # rest of the booted config — same helper as
  # list_receipts_authorization_spec.rb#stub_audit_logs_flag.
  def stub_audit_logs_flag(value)
    conf                                = OT.conf.dup
    features                            = (conf['features'] || {}).dup
    organizations                       = (features['organizations'] || {}).dup
    organizations['audit_logs_enabled'] = value
    features['organizations']           = organizations
    conf['features']                    = features
    allow(OT).to receive(:conf).and_return(conf)
  end

  # :allowed, or :denied. Denial shape (FormError < Problem vs
  # EntitlementRequired < Forbidden) legitimately differs between the two
  # surfaces — what must NOT differ is allowed-vs-denied, so both branches of
  # this codebase's error hierarchy count as a denial here.
  def verdict
    yield
    :allowed
  rescue Onetime::Problem, Onetime::Forbidden
    :denied
  end

  def receipts_verdict(entitlement_granted:)
    verdict do
      logic      = V2::Logic::Secrets::ListReceipts.new(strategy_result, { 'scope' => 'org' })
      membership = double('OrganizationMembership', active?: true, status: 'active')
      allow(membership).to receive(:can?) do |entitlement|
        entitlement.to_s == 'api_access' || (entitlement.to_s == 'audit_logs' && entitlement_granted)
      end
      allow(logic).to receive(:auth_org).and_return(organization)
      allow(logic).to receive(:auth_membership).and_return(membership)

      logic.process_params
      logic.raise_concerns
    end
  end

  def activity_verdict(entitlement_granted:)
    verdict do
      logic      = OrganizationAPI::Logic::Organizations::ListSecretActivity.new(
        strategy_result, { 'extid' => organization.extid }
      )
      membership = instance_double(Onetime::OrganizationMembership, active?: true, can?: entitlement_granted)
      allow(Onetime::Organization).to receive(:find_by_extid).with(organization.extid).and_return(organization)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(organization.objid, customer.objid).and_return(membership)

      logic.process_params
      logic.raise_concerns
    end
  end

  [true, false].each do |entitlement_granted|
    context "audit_logs entitlement #{entitlement_granted ? 'granted' : 'withheld'}" do
      %w[false true garbage].each do |flag_value|
        it "agree with ORGS_AUDIT_LOGS_ENABLED=#{flag_value.inspect}" do
          stub_audit_logs_flag(flag_value)

          expect(receipts_verdict(entitlement_granted: entitlement_granted))
            .to eq(activity_verdict(entitlement_granted: entitlement_granted))
        end
      end
    end
  end

  it 'both admit an entitled caller when the flag is not disabled (positive control)' do
    stub_audit_logs_flag('true')

    expect(receipts_verdict(entitlement_granted: true)).to eq(:allowed)
    expect(activity_verdict(entitlement_granted: true)).to eq(:allowed)
  end

  it 'both deny cross-member access once the instance flag is off, regardless of entitlement' do
    stub_audit_logs_flag('false')

    expect(receipts_verdict(entitlement_granted: true)).to eq(:denied)
    expect(activity_verdict(entitlement_granted: true)).to eq(:denied)
  end
end
