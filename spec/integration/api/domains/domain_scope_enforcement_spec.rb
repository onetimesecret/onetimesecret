# spec/integration/api/domains/domain_scope_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Domain-Scope Enforcement (Issue #3384)
# =============================================================================
#
# Verifies that domain-scoped SSO members cannot access domains, brand data,
# images, or perform member operations outside their scope.
#
# Background
# ----------
# OrganizationMembership#domain_scope_id stores the domain's objid when a user
# joins via SSO. can_access_domain?(domain) returns true only if the member is
# org-scoped (nil domain_scope_id) or domain_scope_id matches the domain's objid.
#
# The scope checks sit AFTER entitlement gates, so the test actor must be an
# admin (which carries custom_domains, manage_members, custom_branding) to
# exercise the scope enforcement code paths.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec spec/integration/api/domains/domain_scope_enforcement_spec.rb
#
# =============================================================================

require 'spec_helper'

RSpec.describe 'Domain-scope enforcement (#3384)', type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    require 'domains/logic/base'
    require 'domains/logic/domains/list_domains'
    require 'domains/logic/domains/get_domain'
    require 'domains/logic/domains/get_domain_brand'
    require 'domains/logic/domains/get_domain_image'
    require 'organizations/logic/base'
    require 'organizations/logic/invitations/create_invitation'
    require 'organizations/logic/invitations/resend_invitation'
    require 'organizations/logic/invitations/revoke_invitation'
    require 'organizations/logic/members/remove_member'
    require 'organizations/logic/members/update_member_role'
  end

  let(:run_id) { "scope_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  # Owner creates and owns the org
  let!(:owner) do
    Onetime::Customer.create!(email: "#{run_id}_owner@test.com")
  end

  let!(:organization) do
    org = Onetime::Organization.create!("Scope Test Org #{run_id}", owner, "#{run_id}_org@test.com")
    org.materialize_standalone_entitlements! if org.respond_to?(:materialize_standalone_entitlements!)
    owner_m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
    owner_m&.materialize_for_role! if owner_m&.respond_to?(:materialize_for_role!)
    org
  end

  # Domain A: the domain our scoped admin is locked to
  let!(:domain_a) do
    domain = Onetime::CustomDomain.new
    domain.display_domain = "#{run_id}-a.example.com"
    domain.org_id = organization.objid
    domain.save
    organization.domains.add(domain.objid)
    domain
  end

  # Domain B: a different domain in the same org (off-limits to scoped admin)
  let!(:domain_b) do
    domain = Onetime::CustomDomain.new
    domain.display_domain = "#{run_id}-b.example.com"
    domain.org_id = organization.objid
    domain.save
    organization.domains.add(domain.objid)
    domain
  end

  # Domain-scoped admin: has admin entitlements but is scoped to domain_a.
  # Admin role is required because scope checks sit after entitlement gates
  # (custom_domains, manage_members, custom_branding).
  let!(:scoped_admin) do
    Onetime::Customer.create!(email: "#{run_id}_scoped@test.com")
  end

  let!(:scoped_membership) do
    membership = organization.add_members_instance(
      scoped_admin,
      through_attrs: {
        role: 'admin',
        status: 'active',
        domain_scope_id: domain_a.objid,
      },
    )
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    membership
  end

  # Org-scoped admin: has admin entitlements with no domain restriction.
  # Used as regression control — should see all domains.
  let!(:org_admin) do
    Onetime::Customer.create!(email: "#{run_id}_orgadmin@test.com")
  end

  let!(:org_admin_membership) do
    membership = organization.add_members_instance(
      org_admin,
      through_attrs: {
        role: 'admin',
        status: 'active',
      },
    )
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    membership
  end

  # A regular member to use as a target for member operations
  let!(:target_member) do
    customer = Onetime::Customer.create!(email: "#{run_id}_target@test.com")
    membership = organization.add_members_instance(
      customer,
      through_attrs: { role: 'member', status: 'active' },
    )
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    customer
  end

  after do
    organization.list_domains.each { |d| d.destroy! rescue nil }
    # Clean up all memberships
    [scoped_admin, org_admin, target_member].each do |user|
      m = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, user.objid)
      m&.destroy! rescue nil
    end
    organization&.destroy! rescue nil
    [scoped_admin, org_admin, target_member, owner].each { |u| u&.destroy! rescue nil }
  end

  # Build a StrategyResult double wired to the given customer + the org under test.
  # Matches the metadata shape that OrganizationContext consumes.
  def strategy_result_for(customer)
    double(
      'StrategyResult',
      session: {},
      user: customer,
      authenticated?: true,
      auth_method: 'sessionauth',
      metadata: { organization_context: { organization: organization } },
    )
  end

  # ==========================================================================
  # Fixture sanity: verify the admin actor passes entitlement gates
  # ==========================================================================

  describe 'fixture sanity', :shared_db_state do
    it 'scoped admin has custom_domains entitlement' do
      expect(scoped_membership.can?('custom_domains')).to be(true),
        'Admin must have custom_domains to exercise scope checks'
    end

    it 'scoped admin has manage_members entitlement' do
      expect(scoped_membership.can?('manage_members')).to be(true),
        'Admin must have manage_members to exercise scope checks on invitation/member ops'
    end

    it 'scoped admin is domain-scoped to domain_a' do
      expect(scoped_membership.domain_scoped?).to be(true)
      expect(scoped_membership.domain_scope_id).to eq(domain_a.objid)
    end

    it 'org admin is org-scoped (nil domain_scope_id)' do
      expect(org_admin_membership.org_scoped?).to be(true)
      expect(org_admin_membership.domain_scope_id.to_s).to be_empty
    end
  end

  # ==========================================================================
  # ListDomains: domain-scoped admin sees only their domain
  # ==========================================================================

  describe 'ListDomains scope filtering', :shared_db_state do
    it 'domain-scoped admin sees only their scoped domain' do
      logic = DomainsAPI::Logic::Domains::ListDomains.new(
        strategy_result_for(scoped_admin),
        {},
      )
      logic.raise_concerns
      result = logic.process

      domain_names = result[:records].map { |d| d[:display_domain] }
      expect(domain_names).to include(domain_a.display_domain)
      expect(domain_names).not_to include(domain_b.display_domain),
        "Domain-scoped admin should not see domain_b (#{domain_b.display_domain})"
      expect(result[:count]).to eq(1)
    end

    it 'org-scoped admin sees all domains (no regression)' do
      logic = DomainsAPI::Logic::Domains::ListDomains.new(
        strategy_result_for(org_admin),
        {},
      )
      logic.raise_concerns
      result = logic.process

      domain_names = result[:records].map { |d| d[:display_domain] }
      expect(domain_names).to include(domain_a.display_domain)
      expect(domain_names).to include(domain_b.display_domain)
      expect(result[:count]).to eq(2)
    end
  end

  # ==========================================================================
  # GetDomain: domain-scoped admin denied for out-of-scope domain
  # ==========================================================================

  describe 'GetDomain scope enforcement', :shared_db_state do
    it 'domain-scoped admin can access their scoped domain' do
      logic = DomainsAPI::Logic::Domains::GetDomain.new(
        strategy_result_for(scoped_admin),
        { 'extid' => domain_a.extid },
      )
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'domain-scoped admin is denied access to a different domain' do
      logic = DomainsAPI::Logic::Domains::GetDomain.new(
        strategy_result_for(scoped_admin),
        { 'extid' => domain_b.extid },
      )
      expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
    end

    it 'org-scoped admin can access any domain' do
      logic = DomainsAPI::Logic::Domains::GetDomain.new(
        strategy_result_for(org_admin),
        { 'extid' => domain_b.extid },
      )
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  # ==========================================================================
  # GetDomainBrand: domain-scoped admin denied for out-of-scope domain
  # ==========================================================================

  describe 'GetDomainBrand scope enforcement', :shared_db_state do
    it 'domain-scoped admin is denied brand access for out-of-scope domain' do
      logic = DomainsAPI::Logic::Domains::GetDomainBrand.new(
        strategy_result_for(scoped_admin),
        { 'extid' => domain_b.extid },
      )
      expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
    end

    it 'domain-scoped admin can access brand for their scoped domain' do
      logic = DomainsAPI::Logic::Domains::GetDomainBrand.new(
        strategy_result_for(scoped_admin),
        { 'extid' => domain_a.extid },
      )
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  # ==========================================================================
  # GetDomainImage: domain-scoped admin denied for out-of-scope domain
  # ==========================================================================

  describe 'GetDomainImage scope enforcement', :shared_db_state do
    it 'domain-scoped admin is denied image access for out-of-scope domain' do
      # GetDomainLogo is the concrete subclass
      logic = DomainsAPI::Logic::Domains::GetDomainLogo.new(
        strategy_result_for(scoped_admin),
        { 'extid' => domain_b.extid },
      )
      # Scope check fires before the image-exists check, so we get
      # "Domain not found" not "Image not found"
      expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
    end
  end

  # ==========================================================================
  # authorize_domain_config!: domain-scoped admin denied config writes
  # ==========================================================================
  #
  # authorize_domain_config! is the shared policy used by all config write
  # endpoints (ApiConfig, HomepageConfig, SenderConfig, SsoConfig, UpdateBrand,
  # UpdateImage, RemoveImage). Testing the policy directly covers all of them.
  #

  describe 'authorize_domain_config! scope enforcement', :shared_db_state do
    # authorize_domain_config! gates on manage_org (owner-level) before the
    # scope check. An admin never reaches the scope code. To exercise the
    # scope check itself, we create a second owner scoped to domain_a.
    # This is artificial but tests the defense-in-depth layer.
    let!(:scoped_owner) do
      customer = Onetime::Customer.create!(email: "#{run_id}_scopedowner@test.com")
      # Transfer ownership is complex, so we add as admin and set owner role
      membership = organization.add_members_instance(
        customer,
        through_attrs: {
          role: 'owner',
          status: 'active',
          domain_scope_id: domain_a.objid,
        },
      )
      membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
      customer
    end

    after do
      m = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, scoped_owner.objid)
      m&.destroy! rescue nil
      scoped_owner&.destroy! rescue nil
    end

    # Build a minimal logic class that includes the policy for testing
    let(:policy_test_class) do
      Class.new(DomainsAPI::Logic::Base) do
        include DomainsAPI::Policies::DomainConfigAuthorization

        attr_reader :custom_domain, :organization

        def config_entitlement
          'custom_branding'
        end

        def config_entitlement_error
          'Custom branding requires the custom_branding entitlement.'
        end

        def process_params; end

        def raise_concerns
          authorize_domain_config!(params['extid'])
        end

        def process
          { authorized: true }
        end
      end
    end

    it 'domain-scoped owner is denied config write for out-of-scope domain' do
      logic = policy_test_class.new(
        strategy_result_for(scoped_owner),
        { 'extid' => domain_b.extid },
      )
      expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
    end

    it 'org-scoped owner can write config for any domain' do
      logic = policy_test_class.new(
        strategy_result_for(owner),
        { 'extid' => domain_b.extid },
      )
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'admin is blocked by manage_org entitlement before scope check' do
      # Documents the layered defense: admins never reach the scope check
      # because manage_org is owner-only.
      logic = policy_test_class.new(
        strategy_result_for(scoped_admin),
        { 'extid' => domain_a.extid },
      )
      expect { logic.raise_concerns }.to raise_error(OT::EntitlementRequired)
    end
  end

  # ==========================================================================
  # Member operations: domain-scoped admin cannot create/remove/invite
  # ==========================================================================
  #
  # CreateInvitation, ResendInvitation, RevokeInvitation, UpdateMemberRole,
  # and RemoveMember all gate on domain_scoped? before other role checks.
  #
  # The error_type is :forbidden but the HTTP status is 422 (FormError maps
  # to 422 via otto_hooks.rb). The :forbidden value appears in the response
  # JSON's error_type field, not as the HTTP status code.
  #

  describe 'CreateInvitation scope enforcement', :shared_db_state do
    it 'domain-scoped admin cannot create invitations' do
      logic = OrganizationAPI::Logic::Invitations::CreateInvitation.new(
        strategy_result_for(scoped_admin),
        { 'extid' => organization.extid, 'email' => "invite-#{run_id}@test.com", 'role' => 'member' },
      )
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |e|
        expect(e.error_type).to eq(:forbidden)
        expect(e.error_key).to eq('api.organizations.errors.domain_scoped_forbidden')
      end
    end

    it 'org-scoped admin can create invitations' do
      logic = OrganizationAPI::Logic::Invitations::CreateInvitation.new(
        strategy_result_for(org_admin),
        { 'extid' => organization.extid, 'email' => "invite-#{run_id}@test.com", 'role' => 'member' },
      )
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'RemoveMember scope enforcement', :shared_db_state do
    it 'domain-scoped admin cannot remove members' do
      logic = OrganizationAPI::Logic::Members::RemoveMember.new(
        strategy_result_for(scoped_admin),
        { 'extid' => organization.extid, 'member_extid' => target_member.extid },
      )
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |e|
        expect(e.error_type).to eq(:forbidden)
        expect(e.error_key).to eq('api.organizations.errors.domain_scoped_forbidden')
      end
    end

    it 'org-scoped admin can remove members' do
      logic = OrganizationAPI::Logic::Members::RemoveMember.new(
        strategy_result_for(org_admin),
        { 'extid' => organization.extid, 'member_extid' => target_member.extid },
      )
      # Should pass raise_concerns (role validation allows admin to remove member)
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'UpdateMemberRole scope enforcement', :shared_db_state do
    # UpdateMemberRole gates on manage_org (owner-only) before the scope check,
    # so an admin actor hits EntitlementRequired first. A domain-scoped owner is
    # required to reach (and exercise) the scope guard.
    let!(:scoped_owner) do
      customer = Onetime::Customer.create!(email: "#{run_id}_role_scopedowner@test.com")
      membership = organization.add_members_instance(
        customer,
        through_attrs: {
          role: 'owner',
          status: 'active',
          domain_scope_id: domain_a.objid,
        },
      )
      membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
      customer
    end

    after do
      m = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, scoped_owner.objid)
      m&.destroy! rescue nil
      scoped_owner&.destroy! rescue nil
    end

    it 'domain-scoped owner cannot change member roles' do
      logic = OrganizationAPI::Logic::Members::UpdateMemberRole.new(
        strategy_result_for(scoped_owner),
        { 'extid' => organization.extid, 'member_extid' => target_member.extid, 'role' => 'admin' },
      )
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |e|
        expect(e.error_type).to eq(:forbidden)
        expect(e.error_key).to eq('api.organizations.errors.domain_scoped_forbidden')
      end
    end
  end

  # ==========================================================================
  # GetPermissions bulk mode: domain-scoped admin sees filtered domains
  # ==========================================================================

  describe 'GetPermissions bulk mode scope filtering', :shared_db_state do
    before(:all) do
      require 'account/logic/account/get_permissions'
    end

    def create_auth_result(customer)
      Otto::Security::Authentication::StrategyResult.new(
        session: { 'authenticated' => true, 'external_id' => customer.extid },
        user: customer,
        auth_method: 'sessionauth',
        strategy_name: 'sessionauth',
        metadata: { ip: '127.0.0.1' },
      )
    end

    it 'domain-scoped admin sees only their scoped domain in bulk permissions' do
      auth_result = create_auth_result(scoped_admin)
      logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, {}, 'en')
      logic.process_params
      logic.raise_concerns
      result = logic.process

      org_data = result[:organizations].find { |o| o[:extid] == organization.extid }
      expect(org_data).not_to be_nil, 'Scoped admin should see their organization'

      domain_extids = org_data[:domains].map { |d| d[:extid] }
      expect(domain_extids).to include(domain_a.extid)
      expect(domain_extids).not_to include(domain_b.extid),
        "Domain-scoped admin should not see domain_b in bulk permissions"
    end

    it 'org-scoped admin sees all domains in bulk permissions' do
      auth_result = create_auth_result(org_admin)
      logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, {}, 'en')
      logic.process_params
      logic.raise_concerns
      result = logic.process

      org_data = result[:organizations].find { |o| o[:extid] == organization.extid }
      expect(org_data).not_to be_nil

      domain_extids = org_data[:domains].map { |d| d[:extid] }
      expect(domain_extids).to include(domain_a.extid)
      expect(domain_extids).to include(domain_b.extid)
    end
  end

  # ==========================================================================
  # GetPermissions single-resource mode: domain-scoped admin denied
  # ==========================================================================

  describe 'GetPermissions single-resource scope enforcement', :shared_db_state do
    before(:all) do
      require 'account/logic/account/get_permissions'
    end

    def create_auth_result(customer)
      Otto::Security::Authentication::StrategyResult.new(
        session: { 'authenticated' => true, 'external_id' => customer.extid },
        user: customer,
        auth_method: 'sessionauth',
        strategy_name: 'sessionauth',
        metadata: { ip: '127.0.0.1' },
      )
    end

    it 'domain-scoped admin is denied single-resource lookup for out-of-scope domain' do
      auth_result = create_auth_result(scoped_admin)
      params = { 'resource_type' => 'domain', 'resource_id' => domain_b.extid }
      logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
      logic.process_params

      expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
    end

    it 'domain-scoped admin can lookup their scoped domain' do
      auth_result = create_auth_result(scoped_admin)
      params = { 'resource_type' => 'domain', 'resource_id' => domain_a.extid }
      logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end
  end
end
