# spec/api/account/get_permissions_spec.rb
#
# frozen_string_literal: true

require_relative '../../integration/integration_spec_helper'
require 'rack/test'

# Integration tests for GET /api/account/permissions
#
# Tests cover both modes:
# 1. Bulk mode (no params): Returns all orgs with memberships and domain permissions
# 2. Single-resource mode (with params): Returns permissions for specific resource
#
# Testing approach:
# Tests the logic class directly with real Customer/Organization/OrganizationMembership
# instances, following the pattern established in add_domain_role_gate_spec.rb.
# HTTP-layer integration is tested via Rack::Test.
#
RSpec.describe 'GET /api/account/permissions', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    @previous_authentication_mode = ENV['AUTHENTICATION_MODE']
    ENV['AUTHENTICATION_MODE'] = 'full'

    # Reset registries to clear state from previous test runs
    Onetime::Application::Registry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application
    Onetime.boot! :test

    # Prepare registry
    Onetime::Application::Registry.prepare_application_registry

    # Load logic class
    require 'account/logic/account/get_permissions'
  end

  after(:all) do
    # Put the process back the way the lane started it. The reload above
    # switched the whole rspec process into full mode and the registry was
    # prepared in that mode; a spec that runs later in the same process and
    # signs in through /auth/login (api_v3_bearer_token_spec.rb) would reach
    # Rodauth with no accounts table and fail, depending on the random order.
    if @previous_authentication_mode.nil?
      ENV.delete('AUTHENTICATION_MODE')
    else
      ENV['AUTHENTICATION_MODE'] = @previous_authentication_mode
    end
    Onetime.auth_config.reload!
    Onetime::Application::Registry.reset!
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:run_id) { "perms_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  # Create owner and organization
  let!(:owner) do
    Onetime::Customer.create!(email: "#{run_id}_owner@test.com")
  end

  let!(:organization) do
    org = Onetime::Organization.create!("Permissions Test Org #{run_id}", owner, "#{run_id}_org@test.com")
    org.materialize_standalone_entitlements! if org.respond_to?(:materialize_standalone_entitlements!)
    owner_m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
    owner_m&.materialize_for_role! if owner_m&.respond_to?(:materialize_for_role!)
    org
  end

  # Create a custom domain for the organization
  let!(:custom_domain) do
    domain = Onetime::CustomDomain.new
    domain.display_domain = "#{run_id}.example.com"
    domain.org_id = organization.objid
    domain.save
    organization.domains.add(domain.objid)
    domain
  end

  # Create admin user
  let!(:admin_user) do
    Onetime::Customer.create!(email: "#{run_id}_admin@test.com")
  end

  let!(:admin_membership) do
    membership = organization.add_members_instance(admin_user, through_attrs: { role: 'admin', status: 'active' })
    membership.materialize_for_role!(organization) if membership.respond_to?(:materialize_for_role!)
    membership
  end

  # Create member user (limited permissions)
  let!(:member_user) do
    Onetime::Customer.create!(email: "#{run_id}_member@test.com")
  end

  let!(:member_membership) do
    membership = organization.add_members_instance(member_user, through_attrs: { role: 'member', status: 'active' })
    membership.materialize_for_role!(organization) if membership.respond_to?(:materialize_for_role!)
    membership
  end

  # Create outsider (not a member of the organization)
  let!(:outsider) do
    Onetime::Customer.create!(email: "#{run_id}_outsider@test.com")
  end

  after do
    custom_domain&.destroy! rescue nil
    admin_membership&.destroy! rescue nil
    member_membership&.destroy! rescue nil
    organization&.destroy! rescue nil
    admin_user&.destroy! rescue nil
    member_user&.destroy! rescue nil
    owner&.destroy! rescue nil
    outsider&.destroy! rescue nil
  end

  # Helper to create a session for a user
  def create_session_for(user)
    env 'rack.session', {
      'external_id' => user.extid,
      'authenticated' => true,
      # #4409: hand-seeded sessions need the surface marker the login hooks record.
      Onetime::Session::Surface::KEY => Onetime::Session::Surface::CANONICAL,
      'session_id' => SecureRandom.hex(16)
    }
  end

  # Helper to create authenticated strategy result for logic class testing
  def create_auth_result(customer)
    Otto::Security::Authentication::StrategyResult.new(
      session: { 'authenticated' => true, 'external_id' => customer.extid },
      user: customer,
      auth_method: 'sessionauth',
      strategy_name: 'sessionauth',
      metadata: { ip: '127.0.0.1' }
    )
  end

  describe 'Authentication' do
    context 'when not authenticated' do
      it 'returns 401 Unauthorized' do
        get '/api/account/permissions'
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'organization invitation permissions' do
    let!(:invitation) do
      Onetime::OrganizationMembership.create_invitation!(
        organization: organization, email: "#{run_id}_invitee@test.com", inviter: owner
      )
    end

    after { invitation.destroy! }

    def expect_invitation_access(user, allowed:)
      create_session_for(user)
      get '/api/account/permissions'
      expect(last_response.status).to eq(200)
      org = JSON.parse(last_response.body).fetch('organizations').find { |row| row.fetch('extid') == organization.extid }
      expect(org.fetch('permissions').fetch('can_manage_invitations')).to be(allowed)

      get '/api/account/permissions', resource_type: 'organization', resource_id: organization.extid
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body).fetch('permissions')).to eq(org.fetch('permissions'))

      get "/api/organizations/#{organization.extid}/invitations"
      expect(last_response.status).to eq(allowed ? 200 : 403)
      body = JSON.parse(last_response.body)
      if allowed
        expect(body.fetch('records').map { |record| record.fetch('email') }).to contain_exactly(invitation.invited_email)
        expect(body.fetch('count')).to eq(1)
      else
        expect(body.keys).not_to include('records', 'count', 'upgrade_to')
      end
    end

    [true, false].each do |billing_enabled|
      context "with billing #{billing_enabled ? 'enabled' : 'disabled'}" do
        before do
          allow(Onetime::BillingConfig.instance).to receive(:enabled?).and_return(billing_enabled)
          # A billing plan can omit management permissions. Standalone mode supplies them.
          organization.materialize_entitlements_from_config(entitlements: %w[create_secrets], limits: {}) if billing_enabled
          expect(organization.can?('manage_members')).to be(!billing_enabled)
          [member_membership, admin_membership].each { |mem| mem.materialize_for_role!(organization) }
        end

        it 'allows an organization-wide member with an explicit grant' do
          member_membership.grant_entitlement('manage_members')
          expect_invitation_access(member_user, allowed: true)
        end

        it 'denies an organization-wide admin with a revoke' do
          admin_membership.revoke_entitlement('manage_members')
          expect_invitation_access(admin_user, allowed: false)
        end

        it 'denies a domain-scoped admin with the capability' do
          admin_membership.domain_scope_id = custom_domain.objid
          admin_membership.save
          expect_invitation_access(admin_user, allowed: false)
        end
      end
    end

    it 'reflects the site-operator bypass only within an organization-wide membership' do
      member_user.role = 'colonel'
      member_user.verified = 'true'
      member_user.verified_by = 'email'
      member_user.save
      expect_invitation_access(member_user, allowed: true)

      member_membership.domain_scope_id = custom_domain.objid
      member_membership.save
      expect_invitation_access(member_user, allowed: false)
    end
  end

  describe 'feature and capability permissions for domain incoming settings' do
    [true, false].each do |billing_enabled|
      context "with billing #{billing_enabled ? 'enabled' : 'disabled'}" do
        before do
          allow(Onetime::BillingConfig.instance).to receive(:enabled?).and_return(billing_enabled)
          organization.materialize_entitlements_from_config(entitlements: %w[incoming_secrets], limits: {}) if billing_enabled
        end

        def expect_incoming_decision(user, allowed:)
          create_session_for(user)
          get '/api/account/permissions'
          expect(last_response.status).to eq(200)
          org = JSON.parse(last_response.body).fetch('organizations').find { |row| row.fetch('extid') == organization.extid }
          expect(org.fetch('plan_entitlements')).to include('incoming_secrets')
          expect(org.fetch('plan_entitlements')).not_to include('manage_org')
          capabilities = org.fetch('membership').fetch('role_capabilities')
          expect(capabilities.include?('manage_org')).to be(allowed)
          domain = org.fetch('domains').find { |row| row.fetch('extid') == custom_domain.extid }
          expect(domain.fetch('permissions').fetch('can_manage_incoming')).to be(allowed)
          expect(domain.fetch('permissions').fetch('incoming_feature_required')).to be(false)

          get '/api/account/permissions', resource_type: 'domain', resource_id: custom_domain.extid
          expect(last_response.status).to eq(200)
          target = JSON.parse(last_response.body)
          expect(target.fetch('organization').fetch('plan_entitlements')).to match_array(org.fetch('plan_entitlements'))
          expect(target.fetch('membership').fetch('role_capabilities')).to match_array(capabilities)
          expect(target.fetch('permissions')).to eq(domain.fetch('permissions'))

          get "/api/domains/#{custom_domain.extid}/incoming-config"
          expect(last_response.status).to eq(allowed ? 200 : 403)
        end

        it 'reports both axes for an owner, including a subsequent capability revoke' do
          expect_incoming_decision(owner, allowed: true)
          Onetime::OrganizationMembership.find_by_org_customer(organization.objid, owner.objid).revoke_entitlement('manage_org')
          expect_incoming_decision(owner, allowed: false)
        end

        it 'excludes other domains for a member with a scoped grant' do
          member_membership.domain_scope_id = SecureRandom.uuid
          member_membership.save
          member_membership.grant_entitlement('manage_org')
          create_session_for(member_user)
          get '/api/account/permissions'
          expect(last_response.status).to eq(200)
          org = JSON.parse(last_response.body).fetch('organizations').find { |row| row.fetch('extid') == organization.extid }
          expect(org.fetch('domains')).to be_empty
          expect(org.fetch('membership').fetch('role_capabilities')).to include('manage_org')
          get '/api/account/permissions', resource_type: 'domain', resource_id: custom_domain.extid
          expect(last_response.status).to eq(404)
          get "/api/domains/#{custom_domain.extid}/incoming-config"
          expect(last_response.status).to eq(404)
        end

        it 'identifies a missing organization feature for an otherwise authorized member' do
          organization.update_feature_override('revoke', 'incoming_secrets')
          create_session_for(owner)
          get '/api/account/permissions', resource_type: 'domain', resource_id: custom_domain.extid
          expect(last_response.status).to eq(200)
          expect(JSON.parse(last_response.body).fetch('permissions')).to include(
            'can_manage_incoming' => false, 'incoming_feature_required' => true
          )
          get "/api/domains/#{custom_domain.extid}/incoming-config"
          expect(last_response.status).to eq(422)
          expect(JSON.parse(last_response.body)).to include(
            'error_key' => 'api.domains.errors.incoming_secrets_entitlement_required'
          )
        end
      end
    end
  end

  describe 'domain SSO permissions' do
    let(:owner_membership) { Onetime::OrganizationMembership.find_by_org_customer(organization.objid, owner.objid) }
    let(:sso_enabled) { true }
    let!(:sso_config) { create_sso_config_for(custom_domain) }

    before do
      config = OT.conf.dup
      config['features'] = config.fetch('features').merge(
        'organizations' => config.fetch('features').fetch('organizations').merge('sso_enabled' => sso_enabled)
      )
      allow(OT).to receive(:conf).and_return(OT::Config.wrap(config))
    end

    after { sso_config.destroy! }

    def create_sso_config_for(domain)
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: domain.identifier, provider_type: 'oidc', client_id: 'test-client',
        issuer: 'https://idp.example.com', display_name: domain.display_domain
      )
    end

    def expect_sso_access(user, status:)
      create_session_for(user)
      get '/api/account/permissions'
      expect(last_response.status).to eq(200)
      org = JSON.parse(last_response.body).fetch('organizations').find { |row| row.fetch('extid') == organization.extid }
      expect(org.fetch('permissions')).not_to have_key('can_manage_sso')
      domain = org.fetch('domains').find { |row| row.fetch('extid') == custom_domain.extid }
      expect(domain.fetch('permissions').fetch('can_manage_sso')).to be(status == 200)

      get '/api/account/permissions', resource_type: 'domain', resource_id: custom_domain.extid
      expect(last_response.status).to eq(200)
      target = JSON.parse(last_response.body)
      expect(target.fetch('permissions')).to eq(domain.fetch('permissions'))
      if status == 200
        expect(domain.fetch('verified')).to be(!!custom_domain.ownership_verified)
        expect(target.fetch('domain')).to eq(domain.slice('display_domain', 'verified'))
      else
        expect(domain).not_to have_key('verified')
        expect(target).not_to have_key('domain')
      end

      get "/api/domains/#{custom_domain.extid}/sso"
      expect(last_response.status).to eq(status)
      expect(JSON.parse(last_response.body).key?('record')).to be(status == 200)
    end

    [true, false].each do |billing_enabled|
      context "with billing #{billing_enabled ? 'enabled' : 'disabled'}" do
        before do
          allow(Onetime::BillingConfig.instance).to receive(:enabled?).and_return(billing_enabled)
          if billing_enabled
            organization.materialize_entitlements_from_config(entitlements: %w[api_access custom_domains], limits: {})
          end
          expect(organization.can?('manage_sso')).to be(!billing_enabled)
        end

        it 'allows an owner through the SSO capability on their membership' do
          custom_domain.ownership_verified!(true)
          expect_sso_access(owner, status: 200)
        end

        %w[manage_org manage_sso].each do |capability|
          it "denies an owner whose #{capability} capability is revoked" do
            owner_membership.revoke_entitlement(capability)
            expect_sso_access(owner, status: 403)
          end
        end

        it 'omits the organization and denies SSO to a pending member with both grants' do
          %w[manage_org manage_sso].each { |capability| member_membership.grant_entitlement(capability) }
          member_membership.status = 'pending'
          member_membership.save
          create_session_for(member_user)

          get '/api/account/permissions'
          expect(last_response.status).to eq(200)
          organizations = JSON.parse(last_response.body).fetch('organizations')
          expect(organizations.map { |row| row.fetch('extid') }).not_to include(organization.extid)

          get '/api/account/permissions', resource_type: 'domain', resource_id: custom_domain.extid
          expect(last_response.status).to eq(403)
          expect(JSON.parse(last_response.body).keys).not_to include('permissions', 'domain')

          get "/api/domains/#{custom_domain.extid}/sso"
          expect(last_response.status).to eq(403)
          expect(JSON.parse(last_response.body)).not_to have_key('record')
        end

        context 'with explicit grants scoped to one domain' do
          let!(:other_domain) do
            domain = Onetime::CustomDomain.new(display_domain: "other-#{run_id}.example.com", org_id: organization.objid)
            domain.save
            organization.domains.add(domain.objid)
            domain
          end
          let!(:other_sso_config) { create_sso_config_for(other_domain) }

          after do
            other_sso_config.destroy!
            other_domain.destroy!
          end

          it 'permits only the matching domain' do
            member_membership.domain_scope_id = custom_domain.objid
            member_membership.save
            %w[manage_org manage_sso].each { |capability| member_membership.grant_entitlement(capability) }
            expect_sso_access(member_user, status: 200)

            get '/api/account/permissions'
            org = JSON.parse(last_response.body).fetch('organizations').find { |row| row.fetch('extid') == organization.extid }
            expect(org.fetch('domains').map { |row| row.fetch('extid') }).to contain_exactly(custom_domain.extid)
            get '/api/account/permissions', resource_type: 'domain', resource_id: other_domain.extid
            expect(last_response.status).to eq(404)
            get "/api/domains/#{other_domain.extid}/sso"
            expect(last_response.status).to eq(404)
          end
        end

        it 'uses the organization entitlement for a site operator' do
          member_user.role = 'colonel'
          member_user.verified = 'true'
          member_user.verified_by = 'email'
          member_user.save
          expect_sso_access(member_user, status: billing_enabled ? 422 : 200)
        end
      end
    end

    context 'when tenant SSO is disabled' do
      let(:sso_enabled) { false }

      it 'reports SSO management unavailable even for an owner' do
        expect_sso_access(owner, status: 422)
      end
    end
  end

  describe 'Bulk mode (GET /api/account/permissions)' do
    context 'as owner' do
      before { create_session_for(owner) }

      it 'returns 200 OK' do
        get '/api/account/permissions'
        expect(last_response.status).to eq(200)
      end

      it 'returns organizations array' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        expect(body).to have_key('organizations')
        expect(body['organizations']).to be_an(Array)
        expect(body['organizations'].length).to be >= 1
      end

      it 'reflects a manage_org revocation in both organization and domain permissions' do
        membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, owner.objid)
        membership.revoke_entitlement('manage_org')

        get '/api/account/permissions'
        org = JSON.parse(last_response.body).fetch('organizations').find { |record| record['extid'] == organization.extid }
        expect(org.fetch('permissions')).to include('can_edit' => false, 'can_delete' => false, 'can_manage_settings' => false)
        domain = org.fetch('domains').find { |record| record['extid'] == custom_domain.extid }
        expect(domain.fetch('permissions')).to include('can_view' => true, 'can_delete' => true, 'can_manage_settings' => false)
      end

      it 'limits management permissions to the domain named by the membership' do
        membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, owner.objid)
        membership.domain_scope_id = custom_domain.objid
        membership.save
        get '/api/account/permissions'
        org = JSON.parse(last_response.body).fetch('organizations').find { |record| record['extid'] == organization.extid }
        expect(org.fetch('permissions')).to include('can_edit' => false, 'can_delete' => false, 'can_manage_settings' => false)
        domain = org.fetch('domains').find { |record| record['extid'] == custom_domain.extid }
        expect(domain.fetch('permissions')).to include('can_manage_settings' => true)

        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"
        expect(JSON.parse(last_response.body).fetch('permissions')).to eq(org.fetch('permissions'))
      end

      it 'includes the test organization' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        expect(org_data).not_to be_nil
        expect(org_data['display_name']).to include('Permissions Test Org')
      end

      it 'includes membership details with owner role' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        expect(org_data['membership']['role']).to eq('owner')
        expect(org_data['membership']['status']).to eq('active')
      end

      it 'includes owner permissions (full access)' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        permissions = org_data['permissions']

        expect(permissions['can_view']).to be true
        expect(permissions['can_edit']).to be true
        expect(permissions['can_manage_settings']).to be true
      end

      it 'owner can_delete is true for non-default org' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        # Test org is not a default workspace, so owner can delete it
        expect(org_data['is_default']).to be false
        expect(org_data['permissions']['can_delete']).to be true
      end

      it 'includes is_default flag for each organization' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        # Every org should have is_default field
        body['organizations'].each do |org_data|
          expect(org_data).to have_key('is_default')
          expect([true, false]).to include(org_data['is_default'])
        end
      end

      it 'includes domains with permissions' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        expect(org_data['domains']).to be_an(Array)
        expect(org_data['domains'].length).to be >= 1

        domain_data = org_data['domains'].find { |d| d['extid'] == custom_domain.extid }
        expect(domain_data).not_to be_nil
        expect(domain_data['display_domain']).to eq(custom_domain.display_domain)
      end

      # The domain-context picker offers only served domains
      # (CustomDomain#served_as_tenant?); the settings pages list them all.
      it 'reports whether each domain is served' do
        allow(Onetime::CustomDomain).to receive(:ownership_proof_required?).and_return(true)

        served = lambda do
          get '/api/account/permissions'
          org_data = JSON.parse(last_response.body)['organizations'].find { |o| o['extid'] == organization.extid }
          org_data['domains'].find { |d| d['extid'] == custom_domain.extid }['served']
        end

        expect(served.call).to be(false)

        custom_domain.ownership_verified!(true)
        expect(served.call).to be(true)
      end

      it 'includes full domain permissions for owner' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        domain_data = org_data['domains'].find { |d| d['extid'] == custom_domain.extid }
        permissions = domain_data['permissions']

        expect(permissions['can_view']).to be true
        expect(permissions['can_edit']).to be true
        expect(permissions['can_delete']).to be true
        expect(permissions['can_manage_settings']).to be true
      end
    end

    context 'as member' do
      before { create_session_for(member_user) }

      it 'returns 200 OK' do
        get '/api/account/permissions'
        expect(last_response.status).to eq(200)
      end

      it 'includes membership with member role' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        expect(org_data['membership']['role']).to eq('member')
      end

      it 'includes limited permissions (can_view only)' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        permissions = org_data['permissions']

        expect(permissions['can_view']).to be true
        expect(permissions['can_edit']).to be false
        expect(permissions['can_delete']).to be false
        expect(permissions['can_manage_settings']).to be false
      end

      it 'includes limited domain permissions for member' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        domain_data = org_data['domains'].find { |d| d['extid'] == custom_domain.extid }
        permissions = domain_data['permissions']

        # Members lack custom_domains entitlement — cannot view/edit/delete/manage (#3326)
        expect(permissions['can_view']).to be false
        expect(permissions['can_edit']).to be false
        expect(permissions['can_delete']).to be false
        expect(permissions['can_manage_settings']).to be false
      end
    end

    context 'as admin' do
      before { create_session_for(admin_user) }

      it 'reports that an admin without manage_org cannot edit or delete the organization' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        permissions = org_data['permissions']

        expect(permissions['can_view']).to be true
        expect(permissions['can_edit']).to be false
        expect(permissions['can_delete']).to be false
      end
    end
  end

  describe 'Single-resource mode: domain' do
    context 'as owner' do
      before { create_session_for(owner) }

      it 'returns 200 OK for owned domain' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        expect(last_response.status).to eq(200)
      end

      it 'denies domain deletion when custom_domains is revoked from an owner' do
        membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, owner.objid)
        membership.revoke_entitlement('custom_domains')
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"

        expect(JSON.parse(last_response.body).fetch('permissions')).to include('can_delete' => false, 'can_manage_settings' => true)
      end

      it 'returns correct resource_type and resource_id' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        body = JSON.parse(last_response.body)

        expect(body['resource_type']).to eq('domain')
        expect(body['resource_id']).to eq(custom_domain.extid)
      end

      it 'includes organization reference' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        body = JSON.parse(last_response.body)

        expect(body['organization']['extid']).to eq(organization.extid)
        expect(body['organization']['display_name']).to include('Permissions Test Org')
      end

      it 'includes membership details' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        body = JSON.parse(last_response.body)

        expect(body['membership']['role']).to eq('owner')
        expect(body['membership']['status']).to eq('active')
      end

      it 'includes domain permissions' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        body = JSON.parse(last_response.body)

        expect(body['permissions']['can_view']).to be true
      end
    end

    context 'as member' do
      before { create_session_for(member_user) }

      it 'returns 200 OK (member can view domain in their org)' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        expect(last_response.status).to eq(200)
      end

      it 'shows limited permissions' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        body = JSON.parse(last_response.body)

        # Members lack custom_domains entitlement (#3326)
        expect(body['permissions']['can_view']).to be false
        expect(body['permissions']['can_edit']).to be false
        expect(body['permissions']['can_delete']).to be false
      end

      it 'shows member role in membership' do
        get "/api/account/permissions?resource_type=domain&resource_id=#{custom_domain.extid}"
        body = JSON.parse(last_response.body)

        expect(body['membership']['role']).to eq('member')
      end
    end

    # NOTE: When testing non-member access at the HTTP layer, the sessionauth
    # strategy fails because outsider has no organization context, yielding 401
    # before the logic class can raise 403 Unauthorized. The logic class
    # behavior (403) is tested directly in "Logic class direct tests" below.
  end

  describe 'Single-resource mode: organization' do
    context 'as owner' do
      before { create_session_for(owner) }

      it 'returns 200 OK' do
        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"
        expect(last_response.status).to eq(200)
      end

      it 'returns full owner permissions' do
        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"
        body = JSON.parse(last_response.body)

        expect(body['permissions']['can_view']).to be true
        expect(body['permissions']['can_edit']).to be true
        expect(body['permissions']['can_manage_settings']).to be true
      end
    end

    context 'as admin' do
      before { create_session_for(admin_user) }

      it 'reports organization management granted to this admin' do
        admin_membership.grant_entitlement('manage_org')
        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"

        expect(JSON.parse(last_response.body).fetch('permissions')).to include(
          'can_edit' => true, 'can_delete' => true, 'can_manage_settings' => true,
        )
      end

      it 'denies organization edits and deletion without manage_org' do
        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"
        body = JSON.parse(last_response.body)

        expect(body['permissions']['can_view']).to be true
        expect(body['permissions']['can_edit']).to be false
        expect(body['permissions']['can_delete']).to be false
      end
    end

    context 'as member' do
      before { create_session_for(member_user) }

      it 'returns can_view only' do
        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"
        body = JSON.parse(last_response.body)

        expect(body['permissions']['can_view']).to be true
        expect(body['permissions']['can_edit']).to be false
        expect(body['permissions']['can_delete']).to be false
      end
    end

    # NOTE: When testing non-member access at the HTTP layer, the sessionauth
    # strategy fails because outsider has no organization context, yielding 401
    # before the logic class can raise 403 Unauthorized. The logic class
    # behavior (403) is tested directly in "Logic class direct tests" below.
  end

  describe 'Error cases' do
    before { create_session_for(owner) }

    context 'invalid resource_type' do
      it 'returns 422 (FormError)' do
        get '/api/account/permissions?resource_type=secret&resource_id=abc123'
        expect(last_response.status).to eq(422)
      end

      it 'includes error message about valid resource types' do
        get '/api/account/permissions?resource_type=invalid&resource_id=abc123'
        body = JSON.parse(last_response.body)

        # Per ADR-013, error responses use 'error' key, not 'message'
        expect(body['error']).to include('resource_type must be one of')
      end
    end

    context 'nonexistent resource' do
      # The logic class raises OT::RecordNotFound (raise_not_found_error),
      # which the Otto error handler maps to 404.
      it 'returns 404 for nonexistent domain' do
        get '/api/account/permissions?resource_type=domain&resource_id=nonexistent123'
        expect(last_response.status).to eq(404)
      end

      it 'returns 404 for nonexistent organization' do
        get '/api/account/permissions?resource_type=organization&resource_id=nonexistent456'
        expect(last_response.status).to eq(404)
      end
    end

    context 'resource_type without resource_id' do
      it 'returns 422 (FormError)' do
        get '/api/account/permissions?resource_type=domain'
        expect(last_response.status).to eq(422)
      end

      it 'includes error message about resource_id being required' do
        get '/api/account/permissions?resource_type=domain'
        body = JSON.parse(last_response.body)

        # Per ADR-013, error responses use 'error' key, not 'message'
        expect(body['error']).to include('resource_id is required')
      end
    end
  end

  describe 'Logic class direct tests' do
    # These tests exercise the logic class directly, complementing
    # the HTTP-layer tests above.

    describe 'bulk mode' do
      it 'owner sees full permissions on their org' do
        auth_result = create_auth_result(owner)
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, {}, 'en')
        logic.process_params
        logic.raise_concerns
        result = logic.process

        org_data = result[:organizations].find { |o| o[:extid] == organization.extid }
        expect(org_data[:permissions][:can_view]).to be true
        expect(org_data[:permissions][:can_edit]).to be true
        expect(org_data[:permissions][:can_manage_settings]).to be true
      end

      it 'member sees limited permissions' do
        auth_result = create_auth_result(member_user)
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, {}, 'en')
        logic.process_params
        logic.raise_concerns
        result = logic.process

        org_data = result[:organizations].find { |o| o[:extid] == organization.extid }
        expect(org_data[:permissions][:can_view]).to be true
        expect(org_data[:permissions][:can_edit]).to be false
      end
    end

    describe 'single-resource mode' do
      it 'non-member raises Forbidden for domain lookup' do
        auth_result = create_auth_result(outsider)
        params = { 'resource_type' => 'domain', 'resource_id' => custom_domain.extid }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::Forbidden)
      end

      it 'invalid resource_type raises FormError' do
        auth_result = create_auth_result(owner)
        params = { 'resource_type' => 'secret', 'resource_id' => 'abc123' }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::FormError, /resource_type must be one of/)
      end

      it 'nonexistent domain raises RecordNotFound' do
        auth_result = create_auth_result(owner)
        params = { 'resource_type' => 'domain', 'resource_id' => 'nonexistent' }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
      end

      it 'non-member raises Forbidden for organization lookup' do
        auth_result = create_auth_result(outsider)
        params = { 'resource_type' => 'organization', 'resource_id' => organization.extid }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::Forbidden)
      end

      it 'nonexistent organization raises RecordNotFound' do
        auth_result = create_auth_result(owner)
        params = { 'resource_type' => 'organization', 'resource_id' => 'nonexistent' }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Organization not found')
      end
    end
  end

  # GAP DOCUMENTATION: Entitlement checks for domain endpoints
  #
  # The following tests document known gaps in entitlement enforcement.
  # These are NOT tests of GetPermissions, but rather documentation that
  # the ListDomains and GetDomain endpoints lack entitlement checks.
  #
  # Issue #3326 mentions these as backend hardening items:
  # - ListDomains should require 'custom_domains' entitlement
  # - GetDomain should require 'custom_domains' entitlement
  #
  # Currently, these endpoints only check organization membership, not
  # whether the user's plan includes the custom_domains entitlement.
  # A user on a plan without custom_domains can still list/view domains
  # if they are a member of an org that has domains.
  #
  # When these entitlement checks are added, add tests here to verify:
  # 1. Member without custom_domains entitlement gets EntitlementRequired
  # 2. Member with custom_domains entitlement can list/view domains
  # 3. AddDomain already has this check (verified in add_domain_role_gate_spec.rb)
end
