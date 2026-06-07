# spec/integration/api/domains/add_domain_role_gate_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for PR #3033 §2: only org owners and admins may add a
# custom domain. Mirrors the try-side coverage at
# try/integration/api/domains/add_domain_role_gate_try.rb, exercising the
# gate by driving the Logic class directly with real Customer / Organization /
# OrganizationMembership instances rather than through the Otto router.
#
# The HTTP-layer integration (sessionauth → 403 / 201) lives in the try test;
# this spec is the supplementary RSpec mirror called out by v3 §9.
RSpec.describe 'AddDomain role gate (#3033)', type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    require 'domains/logic/base'
    require 'domains/logic/domains/add_domain'
  end

  let(:run_id) { "addgate_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  let!(:owner) do
    Onetime::Customer.create!(email: "#{run_id}_owner@test.com")
  end

  let!(:organization) do
    org = Onetime::Organization.create!("Role Gate Org #{run_id}", owner, "#{run_id}_org@test.com")
    # Materialize standalone entitlements for the org (required for membership entitlement checks)
    org.materialize_standalone_entitlements! if org.respond_to?(:materialize_standalone_entitlements!)
    # The owner membership needs to have its entitlements materialized
    owner_m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
    owner_m&.materialize_for_role! if owner_m&.respond_to?(:materialize_for_role!)
    org
  end

  let!(:admin_user) do
    Onetime::Customer.create!(email: "#{run_id}_admin@test.com")
  end

  let!(:member_user) do
    Onetime::Customer.create!(email: "#{run_id}_member@test.com")
  end

  let!(:admin_membership) do
    membership = organization.add_members_instance(admin_user, through_attrs: { role: 'admin' })
    # Materialize entitlements for require_entitlement_in! checks (ADR-012 Stage 3)
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    membership
  end

  let!(:member_membership) do
    membership = organization.add_members_instance(member_user, through_attrs: { role: 'member' })
    # Materialize entitlements (members get limited entitlements per role template)
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    membership
  end

  after do
    organization.list_domains.each { |d| d.destroy! rescue nil }
    admin_membership&.destroy! rescue nil
    member_membership&.destroy! rescue nil
    organization&.destroy! rescue nil
    admin_user&.destroy! rescue nil
    member_user&.destroy! rescue nil
    owner&.destroy! rescue nil
  end

  # Build a StrategyResult double wired to the given customer + the org under
  # test. Matches the metadata shape that OrganizationContext consumes via
  # extract_organization_context.
  def strategy_result_for(customer)
    double(
      'StrategyResult',
      session:        {},
      user:           customer,
      authenticated?: true,
      auth_method:    'sessionauth',
      metadata:       { organization_context: { organization: organization } },
    )
  end

  def build_add_domain_logic(customer, domain:, org_id: nil)
    params = { 'domain' => domain }
    params['org_id'] = org_id if org_id
    DomainsAPI::Logic::Domains::AddDomain.new(strategy_result_for(customer), params)
  end

  describe 'owner role' do
    it 'passes the admin gate' do
      logic = build_add_domain_logic(owner, domain: "#{run_id}-owner.example.com")
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'admin role' do
    # ADR-012 Stage 3: custom_domains is an admin-level entitlement
    # Admins can add custom domains (same as owners)
    it 'passes the admin gate' do
      logic = build_add_domain_logic(admin_user, domain: "#{run_id}-admin.example.com")
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'member role' do
    it 'rejects with Onetime::EntitlementRequired (ADR-012 Stage 3)' do
      # Members have membership but lack the custom_domains entitlement,
      # so they get EntitlementRequired rather than Forbidden
      logic = build_add_domain_logic(member_user, domain: "#{run_id}-member.example.com")
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
    end

    it 'tags the error with the entitlement-required i18n key' do
      # Asserting error_key (not the message text) keeps the spec stable across
      # locale-text edits while still catching a missing/renamed key. The HTTP
      # edge resolves the key via ErrorResolver before the response body is
      # rendered — that end-to-end resolution is covered by the try-side
      # integration test (add_domain_role_gate_try.rb test 3c).
      logic = build_add_domain_logic(member_user, domain: "#{run_id}-member-msg.example.com")
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired) do |error|
        expect(error.error_key).to eq('api.entitlements.errors.custom_domains_required')
      end
    end

    it 'does not create a domain when the gate rejects' do
      attempted = "#{run_id}-member-nocreate.example.com"
      logic = build_add_domain_logic(member_user, domain: attempted)
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
      expect(organization.list_domains.map(&:display_domain)).not_to include(attempted)
    end
  end

  describe 'colonel bypass' do
    # Colonels are system admins; verify_organization_admin delegates to
    # verify_one_of_roles!(colonel: true, ...) which short-circuits on
    # has_system_role?('colonel'). The system-role check ALSO requires a
    # verified email (defense-in-depth in authorization_policies.rb).
    let!(:colonel_user) do
      customer = Onetime::Customer.create!(email: "#{run_id}_colonel@test.com")
      customer.role = 'colonel'
      customer.verified = 'true'
      customer.save
      customer
    end

    let!(:colonel_membership) do
      # Membership role intentionally 'member' — colonel should bypass anyway via has_system_role?.
      membership = organization.add_members_instance(colonel_user, through_attrs: { role: 'member' })
      membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
      membership
    end

    after do
      colonel_membership&.destroy! rescue nil
      colonel_user&.destroy! rescue nil
    end

    it 'passes the admin gate via the colonel system-role bypass' do
      logic = build_add_domain_logic(colonel_user, domain: "#{run_id}-colonel.example.com")
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'unverified colonel still trips the gate (defense-in-depth)' do
      # Strip verified flag — system-role check should fail closed.
      colonel_user.verified = nil
      colonel_user.save
      logic = build_add_domain_logic(colonel_user, domain: "#{run_id}-unverified-colonel.example.com")
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe 'member with explicit org_id' do
    let!(:secondary_org) do
      org = Onetime::Organization.create!("Secondary Org #{run_id}", owner, "#{run_id}_secondary@test.com")
      org.materialize_standalone_entitlements! if org.respond_to?(:materialize_standalone_entitlements!)
      org
    end

    let!(:secondary_member_membership) do
      membership = secondary_org.add_members_instance(member_user, through_attrs: { role: 'member' })
      membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
      membership
    end

    after do
      secondary_org.list_domains.each { |d| d.destroy! rescue nil }
      secondary_member_membership&.destroy! rescue nil
      secondary_org&.destroy! rescue nil
    end

    it 'rejects with Onetime::EntitlementRequired — member lacks custom_domains entitlement' do
      logic = build_add_domain_logic(
        member_user,
        domain: "#{run_id}-member-explicit.example.com",
        org_id: secondary_org.objid,
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
    end
  end

  describe 'non-member with explicit org_id (regression: resolution check still runs first)' do
    let!(:foreign_org) do
      Onetime::Organization.create!("Foreign Org #{run_id}", owner, "#{run_id}_foreign@test.com")
    end

    after do
      foreign_org&.destroy! rescue nil
    end

    it 'rejects with FormError before reaching the admin gate' do
      # member_user has no membership in foreign_org, so resolve_target_organization
      # returns nil and raise_form_error('Organization not found or access denied')
      # fires before verify_organization_admin can run.
      logic = build_add_domain_logic(
        member_user,
        domain: "#{run_id}-foreign.example.com",
        org_id: foreign_org.objid,
      )
      expect { logic.raise_concerns }.to raise_error(
        Onetime::FormError,
        /access denied|not found/i,
      )
    end
  end
end
