# spec/integration/all/colonel_membership_entitlement_override_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Load the ColonelAPI application and its dependencies
# (apps/api is in the load path from spec_helper).
require 'colonel/application'

# Integration tests for ManageMembershipEntitlementOverride (#3907) against
# real Redis (port 2121; type: :integration flushes after each example) — the
# membership-scoped sibling of the org-level adapter covered by
# try/integration/api/colonel/manage_entitlement_override_try.rb:
#
#   POST   /api/colonel/organizations/:org_id/members/:member_id/entitlements/grant
#   POST   /api/colonel/organizations/:org_id/members/:member_id/entitlements/revoke
#   DELETE /api/colonel/organizations/:org_id/members/:member_id/entitlements/overrides
#
# The Logic is instantiated directly with a StrategyResult double (mirrors
# colonel_customer_support_spec.rb) so the assertions reach the REAL op, the
# REAL membership model writes, and the REAL audit trail — no HTTP layer.
RSpec.describe 'Colonel membership entitlement overrides', type: :integration do
  def strategy_result_for(user, session: {})
    double(
      'StrategyResult',
      session: session,
      user: user,
      metadata: { ip: '127.0.0.1' },
      auth_method: 'sessionauth',
    )
  end

  def create_customer(email:, role: 'customer', verified: 'true')
    cust          = Onetime::Customer.create!(email: email)
    cust.role     = role
    cust.verified = verified
    cust.save
    cust
  end

  let(:colonel) do
    create_customer(email: "colonel-#{SecureRandom.hex(4)}@example.com", role: 'colonel')
  end

  let(:owner) do
    create_customer(email: "owner-#{SecureRandom.hex(4)}@example.com")
  end

  # Organization.create! creates the owner's ACTIVE membership, so the real
  # find_by_org_customer path resolves it — the target of every override here.
  let(:org) do
    Onetime::Organization.create!("Member Override Org #{SecureRandom.hex(4)}", owner, owner.email)
  end

  def run_logic(params, actor: colonel)
    logic = ColonelAPI::Logic::Colonel::ManageMembershipEntitlementOverride.new(
      strategy_result_for(actor), params,
    )
    logic.raise_concerns
    logic.process
  end

  def membership
    Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
  end

  describe 'grant' do
    it 'writes the override through the op and returns the recomputed record' do
      data = run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.extid,
          'entitlement' => 'custom_branding', 'action' => 'grant' },
      )

      record = data[:record]
      expect(record[:org_id]).to eq(org.extid)
      expect(record[:member_id]).to eq(owner.extid)
      expect(record[:action]).to eq('granted')
      expect(record[:grants]).to include('custom_branding')
      expect(record[:effective_entitlements]).to include('custom_branding')

      # Persisted, not just reported: the membership's grants set holds it.
      expect(membership.entitlements_grants.member?('custom_branding')).to be(true)
    end

    it 'records EXACTLY ONE audit event from the op (adapter must not double-record)' do
      before_count = Onetime::AdminAuditEvent.count

      run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.extid,
          'entitlement' => 'audit_probe', 'action' => 'grant' },
      )

      event = Onetime::AdminAuditEvent.recent(1).first
      expect(Onetime::AdminAuditEvent.count - before_count).to eq(1)
      expect(event['verb']).to eq('membership.entitlement.grant')
      expect(event['actor']).to eq(colonel.extid)
      expect(event['target']).to eq(owner.extid)
      expect(event['detail']).to eq('org_id' => org.extid, 'entitlement' => 'audit_probe')
    end

    it 'resolves the member by email (email-tolerant identifier handling)' do
      data = run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.email,
          'entitlement' => 'custom_branding', 'action' => 'grant' },
      )

      expect(data[:record][:member_id]).to eq(owner.extid)
    end
  end

  describe 'revoke' do
    it 'moves the entitlement into revokes and out of the effective set' do
      data = run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.extid,
          'entitlement' => 'api_access', 'action' => 'revoke' },
      )

      record = data[:record]
      expect(record[:action]).to eq('revoked')
      expect(record[:revokes]).to include('api_access')
      expect(record[:effective_entitlements]).not_to include('api_access')
      expect(membership.entitlements_revokes.member?('api_access')).to be(true)
    end
  end

  describe 'clear' do
    it "maps the DELETE route's nil action to clear and wipes both sets" do
      run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.extid,
          'entitlement' => 'custom_branding', 'action' => 'grant' },
      )
      run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.extid,
          'entitlement' => 'api_access', 'action' => 'revoke' },
      )

      # A client-sent entitlement on the DELETE path is ignored by clear and
      # must NOT be echoed back — the contract is `entitlement: null` on clear.
      data = run_logic(
        { 'org_id' => org.extid, 'member_id' => owner.extid, 'action' => nil,
          'entitlement' => 'ignored_by_clear' },
      )

      record = data[:record]
      expect(record[:action]).to eq('cleared')
      expect(record[:entitlement]).to be_nil
      expect(record[:grants]).to eq([])
      expect(record[:revokes]).to eq([])
      expect(membership.entitlements_grants.size).to eq(0)
      expect(membership.entitlements_revokes.size).to eq(0)

      event = Onetime::AdminAuditEvent.recent(1).first
      expect(event['verb']).to eq('membership.entitlement.clear')
      expect(event['detail']).to eq('org_id' => org.extid)
    end
  end

  describe 'refusals' do
    it 'raises Forbidden for a non-colonel caller' do
      regular = create_customer(email: "regular-#{SecureRandom.hex(4)}@example.com")

      logic = ColonelAPI::Logic::Colonel::ManageMembershipEntitlementOverride.new(
        strategy_result_for(regular),
        'org_id' => org.extid, 'member_id' => owner.extid,
        'entitlement' => 'custom_branding', 'action' => 'grant',
      )

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'raises a form error when grant/revoke has no entitlement (constructor-time)' do
      expect do
        ColonelAPI::Logic::Colonel::ManageMembershipEntitlementOverride.new(
          strategy_result_for(colonel),
          'org_id' => org.extid, 'member_id' => owner.extid, 'action' => 'grant',
        )
      end.to raise_error(OT::FormError, /entitlement is required/i)
    end

    it 'raises not-found for an unknown org' do
      logic = ColonelAPI::Logic::Colonel::ManageMembershipEntitlementOverride.new(
        strategy_result_for(colonel),
        'org_id' => 'on_nope', 'member_id' => owner.extid,
        'entitlement' => 'custom_branding', 'action' => 'grant',
      )

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound, /organization not found/i)
    end

    it 'raises not-found when the customer exists but is not a member (:not_found from the op)' do
      outsider = create_customer(email: "outsider-#{SecureRandom.hex(4)}@example.com")

      before_count = Onetime::AdminAuditEvent.count

      expect do
        run_logic(
          { 'org_id' => org.extid, 'member_id' => outsider.extid,
            'entitlement' => 'custom_branding', 'action' => 'grant' },
        )
      end.to raise_error(Onetime::RecordNotFound, /membership not found/i)

      # The op refused before mutating — but a REFUSED privileged mutation is
      # still an attempt, so it lands in the trail with the same verb/target as
      # a success, differing only in result:/detail. (The `raise_concerns`
      # rejections above never reach the op and so record nothing at all.)
      expect(Onetime::AdminAuditEvent.count).to eq(before_count + 1)
      event = Onetime::AdminAuditEvent.recent(1).first
      expect(event['verb']).to eq('membership.entitlement.grant')
      expect(event['target']).to eq(outsider.extid)
      expect(event['result']).to eq('failure')
      expect(event['detail']).to include(
        'reason' => 'not_found', 'org_id' => org.extid, 'entitlement' => 'custom_branding',
      )
    end
  end
end
