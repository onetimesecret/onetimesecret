# apps/web/auth/spec/integration/basicauth_rejection_on_session_routes_spec.rb
#
# frozen_string_literal: true

# Integration test: session-only routes reject BasicAuth callers at Otto layer.
#
# Nine POST routes are restricted to auth=sessionauth (no basicauth in the
# route declaration). This spec sends actual HTTP requests with valid
# BasicAuth credentials to each restricted route and verifies that Otto
# rejects them before the logic layer is reached.
#
# As a positive control, routes that DO declare auth=sessionauth,basicauth
# (e.g., GET /api/account/) are verified to accept the same credentials.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   source .env.test && bundle exec rspec apps/web/auth/spec/integration/basicauth_rejection_on_session_routes_spec.rb --format documentation

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'
require 'json'

RSpec.describe 'BasicAuth rejection on session-only routes', type: :integration do
  include_context 'strategy test'

  # -----------------------------------------------------------------------
  # Rack app: full URL map with all mounted applications
  # -----------------------------------------------------------------------
  # ProductionConfigHelper (included via type: :integration) provides `app`
  # but we override it here to be explicit and ensure the registry is warm.

  def app
    @app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  # Send a POST with BasicAuth credentials and JSON accept header.
  # No session cookie, no CSRF token -- pure API-style request.
  def basic_auth_post(path, body = {})
    header 'Accept', 'application/json'
    header 'Content-Type', 'application/json'
    authorize test_customer.email, test_apikey
    post path, body.to_json
  end

  # Send a GET with BasicAuth credentials and JSON accept header.
  def basic_auth_get(path)
    header 'Accept', 'application/json'
    header 'Content-Type', nil
    authorize test_customer.email, test_apikey
    get path
  end

  # Parse JSON response body.
  def json_body
    JSON.parse(last_response.body)
  end

  # =====================================================================
  # Positive control: BasicAuth strategy authenticates with valid creds
  # =====================================================================
  # Verify that the same credentials used in the rejection tests ARE
  # valid. This confirms the 401s above are due to route restrictions,
  # not invalid credentials. We test the strategy directly because
  # routes that accept BasicAuth may encounter unrelated downstream
  # errors (middleware, handler) that would obscure the auth signal.

  describe 'positive control: BasicAuth credentials are valid' do
    it 'BasicAuthStrategy authenticates the test customer successfully' do
      encoded = Base64.strict_encode64("#{test_customer.email}:#{test_apikey}")
      env = {
        'rack.session' => {},
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_USER_AGENT' => 'Test/1.0',
        'HTTP_AUTHORIZATION' => "Basic #{encoded}",
      }

      result = basic_auth_strategy.authenticate(env, 'basicauth')

      expect(result).to be_a(Otto::Security::Authentication::StrategyResult),
        "Expected BasicAuth to succeed with valid credentials, got: #{result.class}"
      expect(result.authenticated?).to be(true),
        "Expected result.authenticated? to be true"
      expect(result.user.custid).to eq(test_customer.custid)
    end

    it 'SessionAuthStrategy rejects the same request (no session)' do
      encoded = Base64.strict_encode64("#{test_customer.email}:#{test_apikey}")
      env = {
        'rack.session' => {},
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_USER_AGENT' => 'Test/1.0',
        'HTTP_AUTHORIZATION' => "Basic #{encoded}",
      }

      result = session_auth_strategy.authenticate(env, 'sessionauth')

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure),
        "Expected SessionAuth to fail for BasicAuth-only request, got: #{result.class}"
    end

    it 'routes that declare basicauth DO list it in auth requirements' do
      # Verify the route declarations match our expectation by checking
      # that GET / in Account API includes basicauth
      routes_file = File.join(Onetime::HOME, 'apps/api/account/routes.txt')
      get_account_line = File.readlines(routes_file).find { |l| l.match?(%r{^GET\s+/\s}) }

      expect(get_account_line).to include('basicauth'),
        "Expected GET / in Account API to accept basicauth: #{get_account_line}"
    end
  end

  # =====================================================================
  # Session-only Account API routes (mounted under /api/account)
  # =====================================================================
  # These routes declare auth=sessionauth only. BasicAuth credentials
  # should be rejected because sessionauth checks session['authenticated'],
  # which is absent/false for BasicAuth requests (no session cookie).

  describe 'session-only Account API routes reject BasicAuth' do
    # Map of path => description for the 7 restricted account routes
    {
      '/api/account/destroy' => 'DestroyAccount',
      '/api/account/change-password' => 'UpdatePassword',
      '/api/account/update-domain-context' => 'UpdateDomainContext',
      '/api/account/apitoken' => 'GenerateAPIToken',
      '/api/account/change-email' => 'RequestEmailChange',
      '/api/account/update-notification-preference' => 'UpdateNotificationPreference',
      '/api/account/resend-email-change-confirmation' => 'ResendEmailChangeConfirmation',
    }.each do |path, logic_name|
      it "POST #{path} (#{logic_name}) returns 401" do
        basic_auth_post path

        expect(last_response.status).to eq(401),
          "Expected POST #{path} to reject BasicAuth with 401, got #{last_response.status}: #{last_response.body}"
      end

      it "POST #{path} (#{logic_name}) returns JSON error body" do
        basic_auth_post path

        expect(last_response.content_type).to include('application/json')
        body = json_body
        expect(body).to have_key('error'),
          "Expected JSON error key in response for POST #{path}, got: #{body.inspect}"
      end
    end
  end

  # =====================================================================
  # Session-only Domains API routes (mounted under /api/domains)
  # =====================================================================
  # These routes declare auth=sessionauth only.

  describe 'session-only Domains API routes reject BasicAuth' do
    it 'POST /api/domains/add (AddDomain) returns 401' do
      basic_auth_post '/api/domains/add'

      expect(last_response.status).to eq(401),
        "Expected POST /api/domains/add to reject BasicAuth with 401, got #{last_response.status}: #{last_response.body}"
    end

    it 'POST /api/domains/add (AddDomain) returns JSON error body' do
      basic_auth_post '/api/domains/add'

      expect(last_response.content_type).to include('application/json')
      body = json_body
      expect(body).to have_key('error')
    end

    it 'POST /api/domains/:extid/remove (RemoveDomain) returns 401' do
      # Use a dummy extid -- the auth layer rejects before routing
      # reaches the logic class, so the extid value is irrelevant.
      basic_auth_post '/api/domains/fake-extid-12345/remove'

      expect(last_response.status).to eq(401),
        "Expected POST /api/domains/:extid/remove to reject BasicAuth with 401, got #{last_response.status}: #{last_response.body}"
    end

    it 'POST /api/domains/:extid/remove (RemoveDomain) returns JSON error body' do
      basic_auth_post '/api/domains/fake-extid-12345/remove'

      expect(last_response.content_type).to include('application/json')
      body = json_body
      expect(body).to have_key('error')
    end
  end

  # =====================================================================
  # Verify auth rejection happens at Otto routing layer, not logic layer
  # =====================================================================
  # The error message should come from Otto's RouteAuthWrapper, not from
  # the logic class's raise_concerns method.

  describe 'rejection is at the auth strategy layer (not logic layer)' do
    it 'error message indicates authentication failure, not a form/logic error' do
      basic_auth_post '/api/account/destroy'

      body = json_body
      # Otto's ResponseBuilder returns "Authentication Required" for auth failures
      expect(body['error']).to eq('Authentication Required'),
        "Expected Otto auth-layer rejection message, got: #{body.inspect}"
    end

    it 'response does not contain logic-layer error markers' do
      basic_auth_post '/api/account/apitoken'

      body = json_body
      # Logic-layer errors use different keys (e.g., 'message' with form details)
      # or raise OT::FormError (status 422). A 401 with 'Authentication Required'
      # confirms the request never reached the logic class.
      expect(last_response.status).to eq(401)
      expect(body['error']).to eq('Authentication Required')
    end
  end
end
