# apps/web/auth/spec/integration/pending_plan_intent_flow_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Pending Plan Intent Flow (Issue #3126)
# =============================================================================
#
# Tests the full signup-to-checkout redirect flow when users come from the
# pricing page with a plan selection.
#
# Flow under test:
# 1. User visits /signup?product=X&interval=Y
# 2. after_create_account captures intent to Customer.pending_plan_intent
# 3. User verifies email (simulated by calling verify_account endpoint)
# 4. after_verify_account surfaces intent -> sets session redirect
# 5. verify_account_redirect reads session -> redirects to /billing/plans/X/Y
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/pending_plan_intent_flow_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'Pending plan intent flow (issue #3126)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full app and application registry via the shared helper so the
    # REAL Auth::Config (a Rodauth::Auth subclass) loads — along with
    # Auth::Config::Hooks::Billing and Auth::Operations (config.rb requires
    # operations.rb, which requires create_customer/create_default_workspace).
    #
    # Do NOT fabricate `module Auth::Config::Hooks` here. Opening Config with the
    # `module` keyword makes Auth::Config a plain Module and poisons the constant
    # for every spec sharing this process: the registry's
    # `class Config < Rodauth::Auth` then raises "TypeError: Config is not a
    # class" and boot is marked permanently not-ready. That regression broke the
    # issue #3221 invite-signup integration spec whenever the two ran together.
    boot_onetime_app

    # Load billing dependencies for plan validation
    begin
      require_relative '../../../../billing/lib/plan_resolver'
    rescue LoadError
      # Billing may not be available in all environments
    end
  end

  before do
    # Skip if auth database not configured
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end
  end

  # Track created resources for cleanup
  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:created_account_ids) { [] }

  after do
    created_organizations.each do |org|
      org.delete! if org&.exists?
    rescue StandardError
      # Non-fatal cleanup error
    end

    created_customers.each do |customer|
      customer.delete! if customer&.exists?
    rescue StandardError
      # Non-fatal cleanup error
    end

    created_account_ids.each do |account_id|
      Auth::Database.connection[:accounts].where(id: account_id).delete
    rescue StandardError
      # Non-fatal cleanup error
    end
  end

  def unique_test_email(prefix = 'plan-intent')
    "#{prefix}-#{SecureRandom.hex(8)}@integration-test.example.com"
  end

  def create_test_account(email:, extid: nil)
    db = Auth::Database.connection
    extid ||= SecureRandom.uuid
    account_id = db[:accounts].insert(
      email: email,
      status_id: 1, # verified status
      external_id: extid,
      created_at: Time.now,
      updated_at: Time.now
    )
    created_account_ids << account_id
    { id: account_id, email: email, external_id: extid, extid: extid }
  end

  # Establish a session, fetch the CSRF token, then POST a JSON login to the
  # rodauth endpoint (mounted at /auth). The full Rack app enforces CSRF, so a
  # raw post without the shrimp token returns 403 Forbidden.
  def csrf_login(email, password = TEST_PASSWORD)
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/login', JSON.generate(login: email, password: password, shrimp: token)
  end

  # ==========================================================================
  # Intent Capture Tests
  # ==========================================================================

  describe 'intent capture in after_create_account' do
    it 'captures product and interval from request params' do
      email = unique_test_email('capture')
      account = create_test_account(email: email)

      # Simulate request params that would be present after signup redirect
      product = 'identity_plus_v1'
      interval = 'monthly'
      source_url = "/auth/create-account?product=#{product}&interval=#{interval}"

      # Build intent JSON (same format as hook)
      intent = {
        product: product,
        interval: interval,
        captured_at: Time.now.utc.iso8601,
        source_url: source_url,
      }.to_json

      # Create customer and set intent (simulating hook behavior)
      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set intent as hook would
      customer.pending_plan_intent = intent

      # Verify intent was captured
      expect(customer.pending_plan_intent.value).to eq(intent)

      parsed = JSON.parse(customer.pending_plan_intent.value)
      expect(parsed['product']).to eq('identity_plus_v1')
      expect(parsed['interval']).to eq('monthly')
    end

    it 'does not capture intent when product is missing' do
      email = unique_test_email('no-product')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Simulate hook logic with missing product
      product = nil
      interval = 'monthly'

      if product.to_s.strip != '' && interval.to_s.strip != ''
        customer.pending_plan_intent = { product: product, interval: interval }.to_json
      end

      # Intent should not be set
      expect(customer.pending_plan_intent.value.to_s).to eq('')
    end

    it 'does not capture intent when interval is missing' do
      email = unique_test_email('no-interval')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Simulate hook logic with missing interval
      product = 'identity_plus_v1'
      interval = ''

      if product.to_s.strip != '' && interval.to_s.strip != ''
        customer.pending_plan_intent = { product: product, interval: interval }.to_json
      end

      # Intent should not be set
      expect(customer.pending_plan_intent.value.to_s).to eq('')
    end
  end

  # ==========================================================================
  # Intent Surfacing Tests
  # ==========================================================================

  describe 'intent surfacing in after_verify_account' do
    let(:session) { {} }

    # Uses the production extract_pending_plan_intent method to ensure tests
    # match actual behavior (including clearing via delete!).
    def surface_plan_intent(customer:, session:, plan_valid: true)
      pending_intent = customer.pending_plan_intent&.value

      return { surfaced: false, reason: :no_intent } if pending_intent.to_s.strip == ''

      # Use production module method which handles JSON parsing and clearing via delete!
      product, interval = Auth::Config::Hooks::Billing.extract_pending_plan_intent(customer)

      return { surfaced: false, reason: :invalid_json } if product.nil? && interval.nil? && pending_intent.to_s.strip != ''

      unless product && interval
        return { surfaced: false, reason: :missing_fields }
      end

      # In production, we'd validate with Billing::PlanResolver
      # For tests, use the plan_valid parameter
      unless plan_valid
        return { surfaced: false, reason: :plan_not_found }
      end

      # Set session redirect
      session['plan_checkout_redirect'] = "/billing/plans/#{product}/#{interval}"

      { surfaced: true, product: product, interval: interval }
    end

    it 'sets session redirect when valid intent exists' do
      email = unique_test_email('surface')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set intent
      intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
      customer.pending_plan_intent = intent

      # Surface intent
      result = surface_plan_intent(customer: customer, session: session)

      expect(result[:surfaced]).to be true
      expect(session['plan_checkout_redirect']).to eq('/billing/plans/identity_plus_v1/monthly')
    end

    it 'clears intent after surfacing (single-use)' do
      email = unique_test_email('single-use')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set intent
      intent = { product: 'team_plus_v1', interval: 'yearly' }.to_json
      customer.pending_plan_intent = intent

      # First surfacing
      first_result = surface_plan_intent(customer: customer, session: session)
      expect(first_result[:surfaced]).to be true

      # Intent should be cleared
      expect(customer.pending_plan_intent.value.to_s).to eq('')

      # Second surfacing should fail
      second_session = {}
      second_result = surface_plan_intent(customer: customer, session: second_session)
      expect(second_result[:surfaced]).to be false
      expect(second_result[:reason]).to eq(:no_intent)
    end

    it 'does not set redirect when no intent exists' do
      email = unique_test_email('no-intent')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # No intent set

      result = surface_plan_intent(customer: customer, session: session)

      expect(result[:surfaced]).to be false
      expect(result[:reason]).to eq(:no_intent)
      expect(session).not_to have_key('plan_checkout_redirect')
    end

    it 'does not surface corrupted intent but leaves it in place for debugging' do
      email = unique_test_email('corrupted')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set corrupted intent
      corrupted_value = 'not-valid-json{{'
      customer.pending_plan_intent = corrupted_value

      result = surface_plan_intent(customer: customer, session: session)

      expect(result[:surfaced]).to be false
      expect(result[:reason]).to eq(:invalid_json)
      # Production does NOT clear on parse error - allows debugging/retry
      expect(customer.pending_plan_intent.value).to eq(corrupted_value)
    end

    it 'clears intent after parse even when plan no longer exists' do
      email = unique_test_email('discontinued')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set intent for discontinued plan
      intent = { product: 'discontinued_plan', interval: 'monthly' }.to_json
      customer.pending_plan_intent = intent

      result = surface_plan_intent(customer: customer, session: session, plan_valid: false)

      expect(result[:surfaced]).to be false
      expect(result[:reason]).to eq(:plan_not_found)
      # Production clears intent after successful JSON parse (before validation)
      expect(customer.pending_plan_intent.value.to_s).to eq('')
    end
  end

  # ==========================================================================
  # Redirect Behavior Tests
  # ==========================================================================

  describe 'verify_account_redirect behavior' do
    def verify_account_redirect(session)
      session.delete('plan_checkout_redirect') || '/account'
    end

    it 'returns checkout URL when intent was surfaced' do
      session = { 'plan_checkout_redirect' => '/billing/plans/identity_plus_v1/monthly' }

      redirect = verify_account_redirect(session)

      expect(redirect).to eq('/billing/plans/identity_plus_v1/monthly')
      expect(session).not_to have_key('plan_checkout_redirect')
    end

    it 'returns /account when no intent was surfaced' do
      session = {}

      redirect = verify_account_redirect(session)

      expect(redirect).to eq('/account')
    end

    it 'clears session key after reading (single-use)' do
      session = { 'plan_checkout_redirect' => '/billing/plans/team_plus_v1/yearly' }

      first_redirect = verify_account_redirect(session)
      second_redirect = verify_account_redirect(session)

      expect(first_redirect).to eq('/billing/plans/team_plus_v1/yearly')
      expect(second_redirect).to eq('/account') # Key was deleted
    end
  end

  # ==========================================================================
  # Intent TTL Tests
  # ==========================================================================

  describe 'intent TTL behavior' do
    it 'defines the pending_plan_intent field on the model' do
      # Documentation test: the actual 24h TTL is enforced by Redis. Here we only
      # confirm the field is declared so the accessor exists. (Familia v2 has no
      # `string_fields` introspection method; the field surfaces as an instance
      # accessor.)
      expect(Onetime::Customer.new).to respond_to(:pending_plan_intent)
    end
  end

  # ==========================================================================
  # URL Construction Tests
  # ==========================================================================

  describe 'checkout redirect URL format' do
    it 'constructs correct URL for identity_plus monthly' do
      product = 'identity_plus_v1'
      interval = 'monthly'
      url = "/billing/plans/#{product}/#{interval}"

      expect(url).to eq('/billing/plans/identity_plus_v1/monthly')
    end

    it 'constructs correct URL for team_plus yearly' do
      product = 'team_plus_v1'
      interval = 'yearly'
      url = "/billing/plans/#{product}/#{interval}"

      expect(url).to eq('/billing/plans/team_plus_v1/yearly')
    end

    it 'handles special characters in product name' do
      product = 'plan-with-dashes_v1'
      interval = 'monthly'
      url = "/billing/plans/#{product}/#{interval}"

      expect(url).to eq('/billing/plans/plan-with-dashes_v1/monthly')
    end
  end

  # ==========================================================================
  # Cross-Session Login Flow Tests (pending_plan_intent fallback)
  # ==========================================================================
  #
  # Tests the scenario where a user signs up with plan params, the intent is
  # stored in customer.pending_plan_intent, and then they log in from a
  # different session (no session keys) and expect billing_redirect.

  describe 'cross-session login flow with pending_plan_intent' do
    # Uses the production Auth::Config::Hooks::Billing.extract_pending_plan_intent
    # method to ensure tests match actual behavior.
    def add_billing_redirect_to_response(session:, json_response:, customer:, plan_valid: true)
      product  = session[:billing_product]
      interval = session[:billing_interval]

      # Fallback to pending_plan_intent when session keys are empty
      # Uses production module method for extraction
      if product.nil? && interval.nil? && customer
        product, interval = Auth::Config::Hooks::Billing.extract_pending_plan_intent(customer)
      end

      return unless product && interval

      if plan_valid
        json_response[:billing_redirect] = {
          product: product,
          interval: interval,
          valid: true,
        }
      else
        json_response[:billing_redirect] = {
          product: product,
          interval: interval,
          valid: false,
          error: "Plan not found: #{product}_#{interval}",
        }
      end

      # Clear session keys after use
      session.delete(:billing_product)
      session.delete(:billing_interval)
    end

    it 'returns billing_redirect from pending_plan_intent on fresh login session' do
      email = unique_test_email('cross-session')
      account = create_test_account(email: email)

      # Step 1: Create customer (simulating signup)
      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Step 2: Set pending_plan_intent (simulating after_create_account hook)
      intent = {
        product: 'identity_plus_v1',
        interval: 'monthly',
        captured_at: Time.now.utc.iso8601,
      }.to_json
      customer.pending_plan_intent = intent

      # Step 3: Simulate fresh login session (no plan keys in session)
      fresh_session = {}
      json_response = {}

      # Step 4: Call add_billing_redirect_to_response (simulating after_login)
      add_billing_redirect_to_response(
        session: fresh_session,
        json_response: json_response,
        customer: customer
      )

      # Verify billing_redirect is returned from pending_plan_intent
      expect(json_response).to have_key(:billing_redirect)
      expect(json_response[:billing_redirect][:product]).to eq('identity_plus_v1')
      expect(json_response[:billing_redirect][:interval]).to eq('monthly')
      expect(json_response[:billing_redirect][:valid]).to be true
    end

    it 'clears pending_plan_intent after successful cross-session login' do
      email = unique_test_email('clear-intent')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set pending_plan_intent
      intent = { product: 'team_plus_v1', interval: 'yearly' }.to_json
      customer.pending_plan_intent = intent

      # Fresh login
      fresh_session = {}
      json_response = {}
      add_billing_redirect_to_response(
        session: fresh_session,
        json_response: json_response,
        customer: customer
      )

      # Intent should be cleared
      expect(customer.pending_plan_intent.value.to_s).to eq('')

      # Second login should not have billing_redirect
      second_session = {}
      second_response = {}
      add_billing_redirect_to_response(
        session: second_session,
        json_response: second_response,
        customer: customer
      )

      expect(second_response).not_to have_key(:billing_redirect)
    end

    it 'session keys take precedence over pending_plan_intent' do
      email = unique_test_email('session-precedence')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set pending_plan_intent to one plan
      intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
      customer.pending_plan_intent = intent

      # Login session has different plan
      session_with_plan = {
        billing_product: 'team_plus_v1',
        billing_interval: 'yearly',
      }
      json_response = {}

      add_billing_redirect_to_response(
        session: session_with_plan,
        json_response: json_response,
        customer: customer
      )

      # Session plan should win
      expect(json_response[:billing_redirect][:product]).to eq('team_plus_v1')
      expect(json_response[:billing_redirect][:interval]).to eq('yearly')

      # pending_plan_intent should NOT be cleared (session was used instead)
      expect(customer.pending_plan_intent.value).to eq(intent)
    end

    it 'handles no customer gracefully (nil account lookup)' do
      fresh_session = {}
      json_response = {}

      expect {
        add_billing_redirect_to_response(
          session: fresh_session,
          json_response: json_response,
          customer: nil
        )
      }.not_to raise_error

      expect(json_response).not_to have_key(:billing_redirect)
    end
  end

  # ==========================================================================
  # True HTTP Integration Tests (full Rodauth stack)
  # ==========================================================================
  #
  # These tests exercise the actual /login endpoint through the full Rack/Rodauth
  # stack, verifying that pending_plan_intent fallback works in production.
  #
  # Unlike the unit-style tests above (which call helper methods directly), these
  # tests make real HTTP requests and verify real JSON responses.
  #
  # @see apps/web/auth/spec/unit/hooks/billing_spec.rb for unit tests of the
  #      extract_pending_plan_intent module method
  #
  describe 'HTTP integration: login with pending_plan_intent fallback' do
    # The login-fallback billing_redirect is produced by the after_login hook in
    # config/hooks/billing.rb, which config.rb only registers when billing is
    # enabled. The shared test boot runs with billing disabled, so the hook never
    # fires here. Skip rather than assert behavior that can't exist in this boot;
    # the always-on intent lifecycle (capture/clear) is covered by the
    # account.rb hooks and the non-HTTP examples above.
    before do
      unless Onetime.billing_config.enabled?
        skip 'billing disabled: after_login billing_redirect hook not registered'
      end
    end

    # Test password used for all HTTP login tests
    TEST_PASSWORD = 'TestPassword123!'

    # Creates a verified account with a password hash for HTTP login testing.
    # Uses Argon2 (Rodauth's default) to hash the password.
    def create_account_with_password(email:, password: TEST_PASSWORD)
      db = Auth::Database.connection
      extid = SecureRandom.uuid

      # Create verified account
      account_id = db[:accounts].insert(
        email: email,
        status_id: 2, # verified status (1=unverified, 2=verified, 3=closed)
        external_id: extid,
        created_at: Time.now,
        updated_at: Time.now
      )
      created_account_ids << account_id

      # Create password hash using Argon2 (Rodauth's default)
      # Cost params match test config in config/features/argon2.rb
      require 'argon2'
      hasher = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
      password_hash = hasher.create(password)

      db[:account_password_hashes].insert(
        id: account_id,
        password_hash: password_hash
      )

      { id: account_id, email: email, external_id: extid }
    end

    it 'returns billing_redirect in JSON response when pending_plan_intent exists' do
      email = unique_test_email('http-login')
      account = create_account_with_password(email: email)

      # Create customer with pending_plan_intent
      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      # Set pending_plan_intent (simulating signup with plan params)
      intent = {
        product: 'identity_plus_v1',
        interval: 'monthly',
        captured_at: Time.now.utc.iso8601,
        source_url: '/signup?product=identity_plus_v1&interval=monthly',
      }.to_json
      customer.pending_plan_intent = intent

      # Make actual HTTP login request
      csrf_login(email)

      # Verify successful login
      expect(last_response.status).to be_between(200, 302)

      # Parse JSON response to check for billing_redirect
      # Rodauth returns JSON for JSON Accept header
      if last_response.content_type&.include?('application/json')
        response_body = JSON.parse(last_response.body)

        expect(response_body).to have_key('billing_redirect')
        expect(response_body['billing_redirect']['product']).to eq('identity_plus_v1')
        expect(response_body['billing_redirect']['interval']).to eq('monthly')
      else
        # If redirect response, billing_redirect should be in session
        # (frontend handles redirect from session in non-JSON flow)
        expect(last_response.status).to eq(302)
      end

      # Verify intent was cleared (single-use)
      customer.pending_plan_intent.reload! if customer.pending_plan_intent.respond_to?(:reload!)
      expect(customer.pending_plan_intent.value.to_s).to eq('')
    end

    it 'clears pending_plan_intent after first successful login' do
      email = unique_test_email('http-clear')
      account = create_account_with_password(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        db: Auth::Database.connection
      )
      customer = operation.call
      created_customers << customer

      customer.pending_plan_intent = { product: 'team_plus_v1', interval: 'yearly' }.to_json

      # First login
      csrf_login(email)

      expect(last_response.status).to be_between(200, 302)

      # Intent should be cleared
      customer.pending_plan_intent.reload! if customer.pending_plan_intent.respond_to?(:reload!)
      expect(customer.pending_plan_intent.value.to_s).to eq('')

      # Second login should not have billing_redirect
      # (need to logout first or use different session)
      clear_cookies
      csrf_login(email)

      if last_response.content_type&.include?('application/json')
        response_body = JSON.parse(last_response.body)
        expect(response_body).not_to have_key('billing_redirect')
      end
    end
  end
end
