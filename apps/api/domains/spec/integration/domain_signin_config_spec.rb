# apps/api/domains/spec/integration/domain_signin_config_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Domain Signin Config API Endpoints
# =============================================================================
#
# Issue: #3814 - Sign-In settings seeded from the wrong resolver
#
# Focused HTTP-surface proof that every signin-config response carries the
# resolution `details` (ADR-024) computed by the CUSTOM-DOMAIN resolver
# (default OFF, opt-in — #3814), not the canonical follows-global resolver:
#
#   GET    /api/domains/:extid/signin-config   (unconfigured -> effective_enabled: false)
#   PUT    /api/domains/:extid/signin-config   (enabled + signin_enabled -> true)
#   DELETE /api/domains/:extid/signin-config   (revert -> false)
#
# Resolver branch coverage (SSO carve-out, explicit signin_enabled=false,
# etc.) lives at the logic level in
# try/integration/api/domains/put_signin_config_try.rb (section 11) — this
# file only pins the HTTP wiring of the three handlers.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=simple (login_as creates a Valkey-backed Customer
#   with a passphrase; full mode routes /auth/login through Rodauth, which
#   has no matching account row, so every login 401s)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec apps/api/domains/spec/integration/domain_signin_config_spec.rb
#
# NOTE: like its siblings in this directory, this file has no mode
# subdirectory, so the rake spec:integration:<mode> lanes do not pick it up.
# It currently runs only when invoked directly.
#
# =============================================================================

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

RSpec.describe 'Domain Signin Config API', type: :integration do
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

  before(:all) do
    Onetime.boot! :test
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:test_email) { "owner-#{test_run_id}@test.local" }
  let(:test_password) { 'Test123!@#' }
  let(:tenant_domain) { "signin-#{test_run_id}.acme-corp.example.com" }

  let!(:test_owner) do
    customer = Onetime::Customer.new(email: test_email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Note: In standalone/test mode (billing disabled), all orgs get
  # STANDALONE_ENTITLEMENTS which includes custom_signin_config automatically.
  let!(:test_organization) do
    Onetime::Organization.create!(
      "Test Org #{test_run_id}",
      test_owner,
      "contact-#{test_run_id}@test.local",
    )
  end

  let!(:test_custom_domain) do
    domain = Onetime::CustomDomain.new(
      display_domain: tenant_domain,
      org_id: test_organization.org_id,
    )
    domain.save
    Onetime::CustomDomain.display_domain_index.put(tenant_domain, domain.domainid)
    domain
  end

  after do
    Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
    Onetime::CustomDomain.display_domain_index.remove(tenant_domain) rescue nil
    test_custom_domain&.destroy! rescue nil
    test_organization&.destroy! rescue nil
    test_owner&.destroy! rescue nil
  end

  def api_path(domain_extid)
    "/api/domains/#{domain_extid}/signin-config"
  end

  def login_as(customer)
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

  describe 'GET /api/domains/:extid/signin-config' do
    context 'when the domain is unconfigured' do
      before do
        login_as(test_owner)
      end

      # Unconfigured is a first-class state (ADR-024): 200 with record: null,
      # not 404, so the settings UI can render the inherited global state.
      it 'returns 200 with a null record' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body).to have_key('record')
        expect(body['record']).to be_nil
      end

      # #3814: custom domains are default-OFF opt-in for sign-in. With no
      # SigninConfig and no tenant SSO, effective_enabled must be false even
      # while the canonical site's sign-in is globally enabled (signin: true
      # in spec/config.test.yaml). This is the seed the settings UI displays;
      # before #3814 it leaked the follows-global resolver's true.
      it 'reports effective_enabled false while global signin is enabled' do
        json_get api_path(test_custom_domain.extid)

        details = json_body['details']
        expect(details).not_to be_nil
        expect(details['global_enabled']).to be true
        expect(details['effective_enabled']).to be false
        expect(details).to have_key('global_restrict_to')
      end
    end
  end

  describe 'PUT /api/domains/:extid/signin-config' do
    before do
      login_as(test_owner)
    end

    context 'opting the domain in (enabled + signin_enabled)' do
      it 'reports effective_enabled true in the PUT response and subsequent GET' do
        csrf_put api_path(test_custom_domain.extid), {
          enabled: true,
          signin_enabled: true,
        }

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body['record']['enabled']).to be true
        expect(body['record']['signin_enabled']).to be true
        expect(body['details']['effective_enabled']).to be true

        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)
        expect(json_body['details']['effective_enabled']).to be true
      end
    end
  end

  describe 'DELETE /api/domains/:extid/signin-config' do
    before do
      login_as(test_owner)
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: test_custom_domain.identifier,
        enabled: true,
        signin_enabled: true,
      )
    end

    # Post-delete resolution truth (ADR-024): the response carries details so
    # the settings UI can re-render without a refetch; the domain reverts to
    # default-OFF (#3814).
    it 'reports effective_enabled false after deleting the config' do
      csrf_delete api_path(test_custom_domain.extid)

      expect(last_response.status).to eq(200)

      body = json_body
      expect(body['success']).to be true
      expect(body['details']['effective_enabled']).to be false
      expect(body['details']['global_enabled']).to be true
    end
  end
end
