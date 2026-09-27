# apps/web/auth/spec/integration/full/authorize_tenant_connect_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #4413 (epic #4408) — exact-domain membership authorization before a
# tenant identity bind.
#
# Drives Auth::Operations::AuthorizeTenantConnect against REAL Valkey
# Customer / Organization / CustomDomain / OrganizationMembership fixtures, the
# same shapes backfill_tenant_issuer_spec.rb uses for the sibling gate in
# BackfillTenantIssuer. The gate is the pre-bind step 7 of the tenant connect
# sequence in docs/authentication/per-domain-sso.md; #3849 wires it into
# account_from_omniauth.
#
# What is proven here:
#   - an ACTIVE membership that can_access_domain? the exact callback domain
#     passes (domain-scoped to that domain, organization-scoped, or the owner);
#   - a member scoped to a SIBLING domain of the same organization is refused —
#     the case organization.member? cannot express;
#   - inactive, missing, organization-set-only and wrong-organization
#     memberships are refused, as are an unknown domain, a domain without an
#     organization, and an account with no Customer;
#   - a refusal is side-effect free: no membership is created, activated or
#     re-scoped, JoinDomainOrganization is never invoked, and account_identities
#     is untouched;
#   - a lookup that raises is a refusal, never a grant.
#
# NOTE ON IDENTIFIERS: CustomDomain#identifier == #objid, a random Familia
# ObjectIdentifier. Domain-scoped memberships name domain.objid in
# domain_scope_id; the gate is handed domain.identifier, as the callback hook
# stamps it into session[:validated_omniauth_domain_id].
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, ORGS_SSO_ENABLED=true
#
# RUN:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/authorize_tenant_connect_spec.rb
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'AuthorizeTenantConnect exact-domain membership gate (#4413)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require_relative '../../../operations/authorize_tenant_connect'
    require_relative '../../../operations/join_domain_organization'
  end

  let(:gate) { Auth::Operations::AuthorizeTenantConnect }
  let(:identities) { Auth::Database.connection[:account_identities] }

  # ==========================================================================
  # Fixture helpers (mirror backfill_tenant_issuer_spec.rb)
  # ==========================================================================

  def unique_email(prefix)
    "#{prefix}-#{SecureRandom.hex(6)}@tenant-connect-test.example.com"
  end

  def build_org
    run   = SecureRandom.hex(6)
    owner = Onetime::Customer.new(email: unique_email("owner-#{run}"))
    owner.save
    org   = Onetime::Organization.create!("Connect Org #{run}", owner, unique_email("contact-#{run}"))
    [org, owner]
  end

  def build_domain_on(org)
    run     = SecureRandom.hex(6)
    display = "secrets-#{run}.tenant-connect-test.example.com"
    domain  = Onetime::CustomDomain.new(display_domain: display, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(display, domain.domainid)
    domain
  end

  def build_customer
    cust = Onetime::Customer.new(email: unique_email('member'))
    cust.save
    cust
  end

  # The Rodauth account row shape the gate reads: only :external_id matters.
  def account_for(customer)
    { id: 42, email: customer.email, external_id: customer.extid }
  end

  def add_member(org, customer, domain_scope_id: nil, role: 'member')
    Onetime::OrganizationMembership.ensure_membership(
      org, customer, role: role, domain_scope_id: domain_scope_id, provisioning_source: 'sso'
    )
  end

  def membership_for(org, customer)
    Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
  end

  # ==========================================================================
  # Authorized
  # ==========================================================================

  describe 'an active membership authorized for the exact callback domain' do
    it 'passes when the membership is scoped to that domain' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: domain.objid)

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result).to be_authorized, "expected authorized, got #{result.reason.inspect}"
      expect(result.reason).to be_nil
      expect(result.custom_domain.identifier).to eq(domain.identifier)
      expect(result.organization.objid).to eq(org.objid)
      expect(result.customer.objid).to eq(customer.objid)
      expect(result.membership.domain_scope_id).to eq(domain.objid)
    end

    it 'passes for the domain-scoped membership the production SSO join creates' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      join        = Auth::Operations::JoinDomainOrganization.new(customer: customer, domain_id: domain.identifier).call
      raise "fixture: join failed #{join.inspect}" unless join[:joined]

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result).to be_authorized, "expected authorized, got #{result.reason.inspect}"
      expect(result.membership.can_access_domain?(domain)).to be(true)
    end

    it 'passes for an organization-scoped membership (no domain_scope_id — the invitation shape)' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: nil)

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result).to be_authorized, "expected authorized, got #{result.reason.inspect}"
      expect(result.membership.org_scoped?).to be(true)
    end

    it 'passes for an organization-scoped membership on EVERY domain the organization owns' do
      org, _owner = build_org
      domain_a    = build_domain_on(org)
      domain_b    = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: nil)

      results = [domain_a, domain_b].map { |d| gate.call(account: account_for(customer), domain_id: d.identifier) }

      expect(results.map(&:authorized?)).to eq([true, true])
    end

    it 'passes for the organization owner' do
      org, owner = build_org
      domain     = build_domain_on(org)

      result = gate.call(account: account_for(owner), domain_id: domain.identifier)

      expect(result).to be_authorized, "expected authorized, got #{result.reason.inspect}"
      expect(result.membership.owner?).to be(true)
    end

    it 'accepts a string-keyed account row' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: domain.objid)

      result = gate.call(account: { 'external_id' => customer.extid }, domain_id: domain.identifier)

      expect(result).to be_authorized
    end
  end

  # ==========================================================================
  # Refused: membership scope
  # ==========================================================================

  describe 'a membership scoped to a sibling domain of the same organization' do
    it 'is refused with :domain_not_authorized' do
      org, _owner = build_org
      domain_a    = build_domain_on(org)
      domain_b    = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: domain_a.objid)
      raise 'fixture: expected org.member? true' unless org.member?(customer)

      result = gate.call(account: account_for(customer), domain_id: domain_b.identifier)

      expect(result).to be_refused
      expect(result.reason).to eq(:domain_not_authorized)
      expect(result.membership.domain_scope_id).to eq(domain_a.objid)
    end

    it 'still passes on the domain the membership names (mismatch is per-callback, not per-account)' do
      org, _owner = build_org
      domain_a    = build_domain_on(org)
      domain_b    = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: domain_a.objid)

      on_a = gate.call(account: account_for(customer), domain_id: domain_a.identifier)
      on_b = gate.call(account: account_for(customer), domain_id: domain_b.identifier)

      expect([on_a.authorized?, on_b.reason]).to eq([true, :domain_not_authorized])
    end

    it 'is refused even after a successful SSO join on the sibling domain' do
      org, _owner = build_org
      domain_a    = build_domain_on(org)
      domain_b    = build_domain_on(org)
      customer    = build_customer
      Auth::Operations::JoinDomainOrganization.new(customer: customer, domain_id: domain_a.identifier).call
      # JoinDomainOrganization on the sibling is the already_member no-op the
      # doc says must never be cited as a substitute for this gate.
      join_b      = Auth::Operations::JoinDomainOrganization.new(customer: customer, domain_id: domain_b.identifier).call
      raise "fixture: expected already_member, got #{join_b.inspect}" unless join_b[:reason] == 'already_member'

      result = gate.call(account: account_for(customer), domain_id: domain_b.identifier)

      expect(result.reason).to eq(:domain_not_authorized)
    end
  end

  describe 'an inactive membership' do
    %w[pending declined expired].each do |status|
      it "is refused with :membership_inactive when status is #{status}" do
        org, _owner       = build_org
        domain            = build_domain_on(org)
        customer          = build_customer
        membership        = add_member(org, customer, domain_scope_id: domain.objid)
        membership.status = status
        membership.save

        result = gate.call(account: account_for(customer), domain_id: domain.identifier)

        expect(result.reason).to eq(:membership_inactive)
        expect(result.membership.status).to eq(status)
      end
    end
  end

  describe 'a missing membership' do
    it 'is refused with :no_membership when the customer is not in the organization' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result.reason).to eq(:no_membership)
      expect(result.customer.objid).to eq(customer.objid)
    end

    it 'is refused with :no_membership when the customer is in the members set with no membership row (members-set-only)' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: nil).destroy!
      raise 'fixture: expected org.member? true with no row' unless org.member?(customer) && membership_for(org, customer).nil?

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result.reason).to eq(:no_membership)
    end

    it 'is refused with :no_membership when the callback domain belongs to a different organization' do
      org_a, _owner_a = build_org
      org_b, _owner_b = build_org
      domain_b        = build_domain_on(org_b)
      customer        = build_customer
      add_member(org_a, customer, domain_scope_id: nil)

      result = gate.call(account: account_for(customer), domain_id: domain_b.identifier)

      expect(result.reason).to eq(:no_membership)
      expect(result.organization.objid).to eq(org_b.objid)
    end
  end

  # ==========================================================================
  # Refused: broken lookup chain
  # ==========================================================================

  describe 'a broken lookup chain' do
    it 'is refused with :no_domain for an unknown domain id' do
      customer = build_customer

      result = gate.call(account: account_for(customer), domain_id: "cd_#{SecureRandom.hex(8)}")

      expect(result.reason).to eq(:no_domain)
    end

    it 'is refused with :no_domain for a blank domain id' do
      customer = build_customer

      results = [nil, ''].map { |d| gate.call(account: account_for(customer), domain_id: d) }

      expect(results.map(&:reason)).to eq([:no_domain, :no_domain])
    end

    it 'is refused with :no_organization when the domain has no primary organization' do
      org, _owner   = build_org
      domain        = build_domain_on(org)
      customer      = build_customer
      add_member(org, customer, domain_scope_id: nil)
      # save refuses a blank org_id; a dangling one models the same state
      # (primary_organization loads nil).
      domain.org_id = "01a0a3d3-0000-7000-8000-#{SecureRandom.hex(6)}"
      domain.save

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result.reason).to eq(:no_organization)
    end

    it 'is refused with :no_account for a nil account or a blank external_id' do
      org, _owner = build_org
      domain      = build_domain_on(org)

      results = [nil, {}, { external_id: '' }, 'not-a-row'].map { |a| gate.call(account: a, domain_id: domain.identifier) }

      expect(results.map(&:reason)).to eq([:no_account, :no_account, :no_account, :no_account])
    end

    it 'is refused with :no_customer when no Customer matches the external_id' do
      org, _owner = build_org
      domain      = build_domain_on(org)

      result = gate.call(account: { external_id: "ur#{SecureRandom.hex(8)}" }, domain_id: domain.identifier)

      expect(result.reason).to eq(:no_customer)
    end

    it 'is refused with :lookup_error when a lookup raises, never authorized' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: domain.objid)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .and_raise(Redis::BaseError, 'connection lost')

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result.reason).to eq(:lookup_error)
      expect(result).to be_refused
    end

    it 'logs a raised lookup as BOTH the error event and the documented refusal event' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      add_member(org, customer, domain_scope_id: domain.objid)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .and_raise(Redis::BaseError, 'connection lost')
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:tenant_connect_membership_lookup_error, hash_including(level: :error, error_class: 'Redis::BaseError'))
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:tenant_connect_membership_refused, hash_including(level: :warn, reason: :lookup_error))
    end
  end

  # ==========================================================================
  # Refusal is side-effect free
  # ==========================================================================

  describe 'a refusal' do
    it 'never invokes JoinDomainOrganization or creates a membership' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      allow(Auth::Operations::JoinDomainOrganization).to receive(:new).and_call_original

      result = gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(result.reason).to eq(:no_membership)
      expect(Auth::Operations::JoinDomainOrganization).not_to have_received(:new)
      expect(membership_for(org, customer)).to be_nil
      expect(org.member?(customer)).to be(false)
    end

    it 'leaves a sibling-scoped membership unchanged (not re-scoped, not deactivated)' do
      org, _owner = build_org
      domain_a    = build_domain_on(org)
      domain_b    = build_domain_on(org)
      customer    = build_customer
      before      = add_member(org, customer, domain_scope_id: domain_a.objid).to_h

      gate.call(account: account_for(customer), domain_id: domain_b.identifier)

      expect(membership_for(org, customer).to_h).to eq(before)
    end

    it 'leaves an inactive membership inactive' do
      org, _owner       = build_org
      domain            = build_domain_on(org)
      customer          = build_customer
      membership        = add_member(org, customer, domain_scope_id: domain.objid)
      membership.status = 'pending'
      membership.save

      gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(membership_for(org, customer).status).to eq('pending')
    end

    it 'leaves account_identities untouched' do
      org, _owner = build_org
      domain      = build_domain_on(org)
      customer    = build_customer
      rows_before = identities.count

      gate.call(account: account_for(customer), domain_id: domain.identifier)

      expect(identities.count).to eq(rows_before)
    end
  end
end
