# spec/integration/api/account/get_permissions_spec.rb
#
# frozen_string_literal: true

require_relative '../../integration_spec_helper'
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
    ENV.delete('AUTHENTICATION_MODE')
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

      it 'includes admin permissions (can_edit but not can_delete)' do
        get '/api/account/permissions'
        body = JSON.parse(last_response.body)

        org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
        permissions = org_data['permissions']

        expect(permissions['can_view']).to be true
        expect(permissions['can_edit']).to be true
        # can_delete is owner-only
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

      it 'returns can_edit but not can_delete' do
        get "/api/account/permissions?resource_type=organization&resource_id=#{organization.extid}"
        body = JSON.parse(last_response.body)

        expect(body['permissions']['can_view']).to be true
        expect(body['permissions']['can_edit']).to be true
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
      # NOTE: The logic class raises OT::Problem for not-found errors, which
      # the Otto error handler maps to 500 (not 404). Only OT::RecordNotFound
      # and OT::MissingSecret are registered as 404 handlers. This is a known
      # gap - the logic class raise_not_found_error should use OT::RecordNotFound.
      # The logic class behavior is tested directly below.
      it 'returns error for nonexistent domain (currently 500, should be 404)' do
        get '/api/account/permissions?resource_type=domain&resource_id=nonexistent123'
        # GAP: Should be 404 but OT::Problem maps to 500
        expect(last_response.status).to eq(500)
      end

      it 'returns error for nonexistent organization (currently 500, should be 404)' do
        get '/api/account/permissions?resource_type=organization&resource_id=nonexistent456'
        # GAP: Should be 404 but OT::Problem maps to 500
        expect(last_response.status).to eq(500)
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

      it 'nonexistent domain raises Problem' do
        auth_result = create_auth_result(owner)
        params = { 'resource_type' => 'domain', 'resource_id' => 'nonexistent' }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::Problem, 'Domain not found')
      end

      it 'non-member raises Forbidden for organization lookup' do
        auth_result = create_auth_result(outsider)
        params = { 'resource_type' => 'organization', 'resource_id' => organization.extid }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::Forbidden)
      end

      it 'nonexistent organization raises Problem' do
        auth_result = create_auth_result(owner)
        params = { 'resource_type' => 'organization', 'resource_id' => 'nonexistent' }
        logic = AccountAPI::Logic::Account::GetPermissions.new(auth_result, params, 'en')
        logic.process_params

        expect { logic.raise_concerns }.to raise_error(OT::Problem, 'Organization not found')
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
