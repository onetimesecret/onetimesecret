# apps/api/domains/spec/integration/domain_signup_config_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Domain Signup Config API Endpoints
# =============================================================================
#
# Issue: #2892 - Per-domain signup validation strategy
#
# Tests the Domain Signup Config REST API endpoints:
#   GET    /api/domains/:extid/signup-config
#   PUT    /api/domains/:extid/signup-config
#   DELETE /api/domains/:extid/signup-config
#
# These endpoints require:
#   1. Authenticated user (session auth)
#   2. User must be organization owner
#   3. Organization must have custom_signup_validation entitlement
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/api/domains/spec/integration/domain_signup_config_spec.rb
#
# =============================================================================

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

RSpec.describe 'Domain Signup Config API', type: :integration do
  include Rack::Test::Methods
  include CsrfTestHelpers

  # Use the full Rack::URLMap so requests traverse the complete middleware
  # stack (including CSRF bypass for /api/* paths) exactly as in production.
  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  # ==========================================================================
  # Test Fixture Setup
  # ==========================================================================

  before(:all) do
    Onetime.boot! :test
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:test_email) { "owner-#{test_run_id}@test.local" }
  let(:test_password) { 'Test123!@#' }
  let(:tenant_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

  # Create owner customer
  let!(:test_owner) do
    customer = Onetime::Customer.new(email: test_email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Create non-owner customer (for authorization tests)
  let!(:test_non_owner) do
    email = "nonowner-#{test_run_id}@test.local"
    customer = Onetime::Customer.new(email: email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Create organization owned by test_owner
  # Note: In standalone/test mode (billing disabled), all orgs get
  # STANDALONE_ENTITLEMENTS which includes custom_signup_validation automatically.
  # The entitlement denial test stubs org.can? to test that code path.
  let!(:test_organization) do
    Onetime::Organization.create!(
      "Test Org #{test_run_id}",
      test_owner,
      "contact-#{test_run_id}@test.local",
    )
  end

  # Create custom domain associated with organization
  let!(:test_custom_domain) do
    domain = Onetime::CustomDomain.new(
      display_domain: tenant_domain,
      org_id: test_organization.org_id,
    )
    domain.save
    Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
    domain
  end

  # Valid signup config params - passthrough strategy
  let(:valid_passthrough_params) do
    {
      validation_strategy: 'passthrough',
      enabled: true,
    }
  end

  # Valid signup config params - domain_allowlist strategy
  let(:valid_allowlist_params) do
    {
      validation_strategy: 'domain_allowlist',
      allowed_signup_domains: ['acme-corp.example.com', 'partner.example.com'],
      enabled: true,
    }
  end

  # Valid signup config params - mx strategy
  let(:valid_mx_params) do
    {
      validation_strategy: 'mx',
      enabled: true,
    }
  end

  # Clean up after each test
  after do
    Onetime::CustomDomain::SignupConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
    Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
    test_custom_domain&.destroy! rescue nil
    test_organization&.destroy! rescue nil
    test_owner&.destroy! rescue nil
    test_non_owner&.destroy! rescue nil
  end

  # ==========================================================================
  # Helper Methods
  # ==========================================================================

  def api_path(domain_extid)
    "/api/domains/#{domain_extid}/signup-config"
  end

  def login_as(customer)
    # Establish session by logging in via auth route
    reset_csrf_token
    csrf_post '/auth/login', {
      login: customer.email,
      password: test_password,
    }

    # Refresh CSRF token after login (session regeneration)
    reset_csrf_token
  end

  def json_get(path)
    header 'Accept', 'application/json'
    header 'Content-Type', nil
    get path
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def csrf_patch(path, params = {})
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token

    patch path, JSON.generate(params.merge(shrimp: csrf_token))
  end

  # ==========================================================================
  # PUT /api/domains/:extid/signup-config - Create/Replace Signup Config
  # ==========================================================================

  describe 'PUT /api/domains/:extid/signup-config' do
    context 'when authenticated as organization owner with entitlement' do
      before do
        login_as(test_owner)
      end

      context 'creating new signup config' do
        it 'creates passthrough config' do
          csrf_put api_path(test_custom_domain.extid), valid_passthrough_params

          expect(last_response.status).to eq(200)

          body = json_body
          expect(body).to have_key('record')
          record = body['record']

          expect(record['validation_strategy']).to eq('passthrough')
          expect(record['enabled']).to be true
          expect(record['requires_allowlist']).to be false
          expect(record['network_validation']).to be false
        end

        it 'creates domain_allowlist config with domains' do
          csrf_put api_path(test_custom_domain.extid), valid_allowlist_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          expect(record['validation_strategy']).to eq('domain_allowlist')
          expect(record['allowed_signup_domains']).to contain_exactly('acme-corp.example.com', 'partner.example.com')
          expect(record['requires_allowlist']).to be true
        end

        it 'creates mx validation config' do
          csrf_put api_path(test_custom_domain.extid), valid_mx_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          expect(record['validation_strategy']).to eq('mx')
          expect(record['network_validation']).to be true
        end

        it 'creates smtp validation config' do
          csrf_put api_path(test_custom_domain.extid), {
            validation_strategy: 'smtp',
            enabled: true,
          }

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          expect(record['validation_strategy']).to eq('smtp')
          expect(record['network_validation']).to be true
        end

        it 'returns user_id in response' do
          csrf_put api_path(test_custom_domain.extid), valid_passthrough_params

          body = json_body
          expect(body['user_id']).to eq(test_owner.extid)
        end

        it 'parses comma-separated allowed_signup_domains string' do
          csrf_put api_path(test_custom_domain.extid), {
            validation_strategy: 'domain_allowlist',
            allowed_signup_domains: 'domain1.com, domain2.com, domain3.com',
            enabled: true,
          }

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['allowed_signup_domains']).to contain_exactly('domain1.com', 'domain2.com', 'domain3.com')
        end
      end

      context 'replacing existing signup config' do
        before do
          # Create initial config
          Onetime::CustomDomain::SignupConfig.create!(
            domain_id: test_custom_domain.identifier,
            validation_strategy: 'passthrough',
            enabled: false,
          )
        end

        it 'replaces all fields with PUT semantics' do
          csrf_put api_path(test_custom_domain.extid), valid_allowlist_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          # Strategy should be replaced
          expect(record['validation_strategy']).to eq('domain_allowlist')
          expect(record['allowed_signup_domains']).to contain_exactly('acme-corp.example.com', 'partner.example.com')
          expect(record['enabled']).to be true
        end

        it 'clears allowed_signup_domains when switching from allowlist to passthrough' do
          # First create with allowlist
          Onetime::CustomDomain::SignupConfig.delete_for_domain!(test_custom_domain.identifier)
          Onetime::CustomDomain::SignupConfig.create!(
            domain_id: test_custom_domain.identifier,
            validation_strategy: 'domain_allowlist',
            allowed_signup_domains: ['old-domain.com'],
            enabled: true,
          )

          # Replace with passthrough
          csrf_put api_path(test_custom_domain.extid), valid_passthrough_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['validation_strategy']).to eq('passthrough')
          # Domains are cleared when not using allowlist
          expect(record['allowed_signup_domains']).to be_empty
        end
      end

      context 'validation errors' do
        it 'returns 422 for missing validation_strategy' do
          csrf_put api_path(test_custom_domain.extid), {
            enabled: true,
          }

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Validation strategy')
        end

        it 'returns 422 for invalid validation_strategy' do
          csrf_put api_path(test_custom_domain.extid), {
            validation_strategy: 'invalid_strategy',
            enabled: true,
          }

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('validation_strategy must be one of')
        end

        it 'returns 422 for domain_allowlist without allowed_signup_domains' do
          csrf_put api_path(test_custom_domain.extid), {
            validation_strategy: 'domain_allowlist',
            enabled: true,
          }

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('allowed_signup_domains')
        end

        it 'returns 422 for domain_allowlist with empty allowed_signup_domains array' do
          csrf_put api_path(test_custom_domain.extid), {
            validation_strategy: 'domain_allowlist',
            allowed_signup_domains: [],
            enabled: true,
          }

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('allowed_signup_domains')
        end
      end
    end

    context 'authorization checks' do
      it 'returns 401 for unauthenticated requests' do
        # No login
        header 'Accept', 'application/json'
        header 'Content-Type', 'application/json'
        put api_path(test_custom_domain.extid), JSON.generate(valid_passthrough_params)

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-member of organization' do
        login_as(test_non_owner)

        csrf_put api_path(test_custom_domain.extid), valid_passthrough_params

        # ADR-012 Stage 4: require_entitlement_in! checks membership first
        # Non-member -> Onetime::Forbidden -> 403
        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['error']).to include('member')
        expect(body['error_key']).to eq('api.organizations.errors.organization_member_required')
      end

      it 'returns 422 when organization lacks custom_signup_validation entitlement' do
        # Login first, then stub the entitlement check.
        # In integration tests with billing disabled, all orgs get STANDALONE_ENTITLEMENTS.
        # We stub can? on the specific org instance to test this code path.
        login_as(test_owner)

        allow_any_instance_of(Onetime::Organization).to receive(:can?).with('custom_signup_validation').and_return(false)

        csrf_put api_path(test_custom_domain.extid), valid_passthrough_params

        # Entitlement check uses raise_form_error -> FormError -> 422
        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('custom_signup_validation')
      end

      it 'returns 404 for non-existent domain' do
        login_as(test_owner)
        csrf_put api_path('nonexistent-domain-extid'), valid_passthrough_params

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('Domain not found')
      end
    end
  end

  # ==========================================================================
  # PATCH /api/domains/:extid/signup-config - Partial Update Signup Config
  # ==========================================================================

  describe 'PATCH /api/domains/:extid/signup-config' do
    context 'when existing config exists' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['original.com', 'partner.com'],
          enabled: false,
        )
      end

      context 'when authenticated as organization owner' do
        before do
          login_as(test_owner)
        end

        it 'updates only provided fields (PATCH semantics)' do
          csrf_patch api_path(test_custom_domain.extid), {
            enabled: true,
          }

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          # Updated field
          expect(record['enabled']).to be true

          # Preserved fields
          expect(record['validation_strategy']).to eq('domain_allowlist')
          expect(record['allowed_signup_domains']).to contain_exactly('original.com', 'partner.com')
        end

        it 'preserves allowed_signup_domains when not provided' do
          csrf_patch api_path(test_custom_domain.extid), {
            enabled: true,
          }

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['allowed_signup_domains']).to contain_exactly('original.com', 'partner.com')
        end

        it 'replaces allowed_signup_domains when provided with values' do
          csrf_patch api_path(test_custom_domain.extid), {
            allowed_signup_domains: ['new-domain.com'],
          }

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['allowed_signup_domains']).to contain_exactly('new-domain.com')
          # Strategy preserved
          expect(record['validation_strategy']).to eq('domain_allowlist')
        end

        it 'updates strategy and preserves enabled state when not provided' do
          # Start enabled
          existing = Onetime::CustomDomain::SignupConfig.find_by_domain_id(test_custom_domain.identifier)
          existing.enabled = 'true'
          existing.save

          csrf_patch api_path(test_custom_domain.extid), {
            validation_strategy: 'passthrough',
          }

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['validation_strategy']).to eq('passthrough')
          expect(record['enabled']).to be true
        end

        it 'returns 422 when switching to domain_allowlist without provided domains and existing is empty' do
          # Replace existing config with non-allowlist that has no domains
          Onetime::CustomDomain::SignupConfig.delete_for_domain!(test_custom_domain.identifier)
          Onetime::CustomDomain::SignupConfig.create!(
            domain_id: test_custom_domain.identifier,
            validation_strategy: 'passthrough',
            enabled: true,
          )

          csrf_patch api_path(test_custom_domain.extid), {
            validation_strategy: 'domain_allowlist',
          }

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('allowed_signup_domains')
        end

        it 'returns 422 for invalid validation_strategy' do
          csrf_patch api_path(test_custom_domain.extid), {
            validation_strategy: 'invalid_strategy',
          }

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('validation_strategy must be one of')
        end
      end
    end

    # End-to-end wiring proof for the PATCH -> audit-log seam fixed in
    # f22c959 ("[#3202] Fix audit-log false positives in PATCH signup config").
    # PatchSignupConfig#normalized_change_params feeds compute_signup_changes a
    # parsed Array (not the raw comma-separated string), so a string-form input
    # whose values match the existing Array (after normalization) must not
    # surface as a change in the audit log. Exhaustive normalization coverage
    # of compute_signup_changes lives in the unit spec at
    # apps/api/domains/spec/logic/signup_config/audit_logger_spec.rb. See #3245.
    context 'audit log change detection' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['a.com', 'b.com'],
          enabled: false,
        )
        login_as(test_owner)
      end

      it 'does not record allowed_signup_domains as changed when string form matches existing array' do
        # Captures the structured payload emitted by log_signup_audit_event,
        # which writes via OT.info as: "[DOMAIN_SIGNUP_AUDIT] <event>", <json>.
        # Forwards to the original logger so normal side-effects are preserved.
        events = []
        allow(OT).to receive(:info).and_wrap_original do |original, *args, **kwargs|
          prefix = args.first.to_s
          if prefix.start_with?('[DOMAIN_SIGNUP_AUDIT]')
            events << {
              event: prefix.sub('[DOMAIN_SIGNUP_AUDIT] ', ''),
              payload: JSON.parse(args[1]),
            }
          end
          original.call(*args, **kwargs)
        end

        csrf_patch api_path(test_custom_domain.extid), {
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: 'a.com, b.com',
        }

        expect(last_response.status).to eq(200)

        update_event = events.find { |e| e[:event] == 'domain_signup_config_updated' }
        expect(update_event).not_to be_nil
        # build_audit_payload omits the :changes key when the hash is empty.
        expect(update_event[:payload]).not_to have_key('changes')
      end
    end

    context 'when no existing config' do
      before do
        login_as(test_owner)
      end

      it 'creates new config when providing all required fields (PATCH-as-create)' do
        csrf_patch api_path(test_custom_domain.extid), valid_passthrough_params

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['validation_strategy']).to eq('passthrough')
        expect(record['enabled']).to be true
      end

      it 'returns 422 when validation_strategy missing for creation' do
        csrf_patch api_path(test_custom_domain.extid), {
          enabled: true,
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Validation strategy')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: false,
        )
      end

      it 'returns 401 for unauthenticated requests' do
        header 'Accept', 'application/json'
        header 'Content-Type', 'application/json'
        patch api_path(test_custom_domain.extid), JSON.generate({ enabled: true })

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-owner of organization' do
        login_as(test_non_owner)
        csrf_patch api_path(test_custom_domain.extid), { enabled: true }

        expect(last_response.status).to eq(403)
      end

      it 'returns 404 for non-existent domain' do
        login_as(test_owner)
        csrf_patch api_path('nonexistent-domain-extid'), { enabled: true }

        expect(last_response.status).to eq(404)
      end
    end
  end

  # ==========================================================================
  # GET /api/domains/:extid/signup-config - Retrieve Signup Config
  # ==========================================================================

  describe 'GET /api/domains/:extid/signup-config' do
    context 'when signup config exists' do
      let!(:existing_config) do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['acme.com', 'partner.com'],
          enabled: true,
        )
      end

      before do
        login_as(test_owner)
      end

      it 'returns the signup config' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body).to have_key('record')
        record = body['record']

        expect(record['validation_strategy']).to eq('domain_allowlist')
        expect(record['allowed_signup_domains']).to contain_exactly('acme.com', 'partner.com')
        expect(record['enabled']).to be true
        expect(record['requires_allowlist']).to be true
        expect(record['network_validation']).to be false
      end

      it 'returns timestamps as integers' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        record = body['record']

        expect(record['created_at']).to be_a(Integer)
        expect(record['updated_at']).to be_a(Integer)
      end

      it 'returns domain_id in response' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        record = body['record']
        expect(record['domain_id']).to eq(test_custom_domain.extid)
      end

      it 'returns user_id in response' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        expect(body['user_id']).to eq(test_owner.extid)
      end
    end

    context 'when signup config does not exist' do
      before do
        login_as(test_owner)
      end

      it 'returns 404' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('Signup configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: true,
        )
      end

      it 'returns 401 for unauthenticated requests' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-owner' do
        login_as(test_non_owner)
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(403)
      end

      it 'returns 404 for non-existent domain' do
        login_as(test_owner)
        json_get api_path('nonexistent-domain-extid')

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('Domain not found')
      end
    end
  end

  # ==========================================================================
  # DELETE /api/domains/:extid/signup-config - Delete Signup Config
  # ==========================================================================

  describe 'DELETE /api/domains/:extid/signup-config' do
    context 'when signup config exists' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['delete-test.com'],
          enabled: true,
        )
        login_as(test_owner)
      end

      it 'deletes the signup config and returns confirmation' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body['success']).to be true
        expect(body['message']).to include('deleted')

        # Verify deletion
        config = Onetime::CustomDomain::SignupConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(config).to be_nil
      end

      it 'returns success message with domain name' do
        csrf_delete api_path(test_custom_domain.extid)

        body = json_body
        expect(body['message']).to include(test_custom_domain.display_domain)
      end
    end

    context 'when signup config does not exist' do
      before do
        login_as(test_owner)
      end

      it 'returns 404' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('Signup configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: test_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: true,
        )
      end

      it 'returns 401 for unauthenticated requests' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-member' do
        login_as(test_non_owner)
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(403)
      end

      it 'returns 404 for non-existent domain' do
        login_as(test_owner)
        csrf_delete api_path('nonexistent-domain-extid')

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('Domain not found')
      end
    end
  end

  # ==========================================================================
  # Strategy-Specific Behavior Tests
  # ==========================================================================

  describe 'strategy-specific behavior' do
    before do
      login_as(test_owner)
    end

    context 'passthrough strategy' do
      it 'does not require allowed_signup_domains' do
        csrf_put api_path(test_custom_domain.extid), {
          validation_strategy: 'passthrough',
          enabled: true,
        }

        expect(last_response.status).to eq(200)
        body = json_body
        expect(body['record']['requires_allowlist']).to be false
      end

      it 'ignores provided allowed_signup_domains' do
        csrf_put api_path(test_custom_domain.extid), {
          validation_strategy: 'passthrough',
          allowed_signup_domains: ['ignored.com'],
          enabled: true,
        }

        expect(last_response.status).to eq(200)
        # Passthrough may store but does not use domains
        body = json_body
        expect(body['record']['validation_strategy']).to eq('passthrough')
      end
    end

    context 'domain_allowlist strategy' do
      it 'normalizes domain names to lowercase' do
        csrf_put api_path(test_custom_domain.extid), {
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['UPPERCASE.COM', 'MixedCase.Org'],
          enabled: true,
        }

        expect(last_response.status).to eq(200)
        body = json_body
        expect(body['record']['allowed_signup_domains']).to contain_exactly('uppercase.com', 'mixedcase.org')
      end

      it 'removes empty strings from domain list' do
        csrf_put api_path(test_custom_domain.extid), {
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: 'valid.com, , another.com, ',
          enabled: true,
        }

        expect(last_response.status).to eq(200)
        body = json_body
        expect(body['record']['allowed_signup_domains']).to contain_exactly('valid.com', 'another.com')
      end
    end

    context 'mx strategy' do
      it 'indicates network validation is required' do
        csrf_put api_path(test_custom_domain.extid), {
          validation_strategy: 'mx',
          enabled: true,
        }

        expect(last_response.status).to eq(200)
        body = json_body
        expect(body['record']['network_validation']).to be true
      end
    end

    context 'smtp strategy' do
      it 'indicates network validation is required' do
        csrf_put api_path(test_custom_domain.extid), {
          validation_strategy: 'smtp',
          enabled: true,
        }

        expect(last_response.status).to eq(200)
        body = json_body
        expect(body['record']['network_validation']).to be true
      end
    end
  end

  # ==========================================================================
  # Enabled/Disabled State Tests
  # ==========================================================================

  describe 'enabled state handling' do
    before do
      login_as(test_owner)
    end

    it 'creates config with enabled=false by default when not specified' do
      csrf_put api_path(test_custom_domain.extid), {
        validation_strategy: 'passthrough',
      }

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['record']['enabled']).to be false
    end

    it 'creates config with enabled=true when specified' do
      csrf_put api_path(test_custom_domain.extid), {
        validation_strategy: 'passthrough',
        enabled: true,
      }

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['record']['enabled']).to be true
    end

    it 'parses string "true" as enabled' do
      csrf_put api_path(test_custom_domain.extid), {
        validation_strategy: 'passthrough',
        enabled: 'true',
      }

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['record']['enabled']).to be true
    end

    it 'parses string "false" as disabled' do
      csrf_put api_path(test_custom_domain.extid), {
        validation_strategy: 'passthrough',
        enabled: 'false',
      }

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['record']['enabled']).to be false
    end
  end
end
