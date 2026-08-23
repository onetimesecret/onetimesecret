# apps/web/auth/spec/integration/full/signin_enabled_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — per-domain `signin_enabled` as an AVAILABILITY GATE
# (ADR-024 "custom domains default OFF, opt-in only";
#  ADR-034#reject-as-not-found-not-forbidden for the reject shape)
# =============================================================================
#
# THE GAP THESE EXAMPLES CLOSE
#
# ADR-024's promise is that a custom domain does NOT get password/email sign-in
# unless its owner explicitly opted in (an *enabled* SigninConfig with
# signin_enabled=true). That promise was enforced in three places and missing
# from a fourth:
#
#   - simple mode — Core::Controllers::Base#signin_enabled? gates POST
#     /auth/login, because in simple mode Core serves that route;
#   - display — the branded masthead's Sign In link and the /signin page
#     availability verdict;
#   - full mode — NOWHERE, except incidentally when a `restrict_to`
#     restriction happened to exist and narrow to :unavailable.
#
# So in FULL mode a custom domain that had never opted in (no SigninConfig at
# all) or had explicitly opted OUT (enabled config, signin_enabled=false) still
# ACCEPTED valid credentials at POST /auth/login and authenticated: 200, real
# session. `Auth::RestrictTo` cannot cover this — it is a NARROWING filter over
# sign-in METHODS and resolves :unrestricted when no restriction exists, which
# by its own explicit invariant must gate nothing ("an unrestricted install must
# not go dark"). The availability half needed its own sibling gate, which is
# Auth::SigninEnabled.
#
# The two regression cases are `D` and `E` in the describes below, and they are
# the reason this file exists. Both were 200 + authenticated before the gate.
#
# WHAT MUST NOT REGRESS IN THE OTHER DIRECTION — the gate NARROWS, it does not
# close. A domain that DID opt in still signs in; canonical/operator hosts are
# untouched; logout, the second-factor ceremony, and SSO stay reachable.
# Gating SSO on this flag in particular would re-create the #4139 regression
# documented at length in signin_config.rb — `signin_enabled` is the
# password/email opt-in and has never governed SSO.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     ORGS_SSO_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/signin_enabled_enforcement_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'
require 'argon2'

RSpec.describe 'per-domain signin_enabled enforcement — full mode (ADR-024 custom domains default OFF)',
  type: :integration do
  include Rack::Test::Methods

  # This gate reads env['onetime.domain_strategy'], so the domains axis has to
  # be ON or DomainStrategy short-circuits, classifies EVERY request
  # :canonical, routes the gate down its operator branch and every example
  # here passes vacuously. The context also installs a parseable operator host
  # (`canonical_host`), without which the canonical set is empty and even the
  # operator host classifies :invalid — the tenant-safe default-OFF branch
  # (ADR-024#operator-defaults-require-positive-classification), i.e. a 404 for
  # a reason that has nothing to do with what these examples assert.
  #
  # `.example.com`, matching the tenant fixture hosts below: those are
  # registered CustomDomains, so they hit Chooserator's registration arm ahead
  # of the peer sweep and keep :custom regardless.
  include_context 'domains enabled', 'operator-signin-gate.example.com'

  before(:all) { boot_onetime_app }

  let(:run_id)   { SecureRandom.hex(6) }
  let(:password) { 'TestPassword123!' }

  # A REAL, verified account in the BOOTED APP's OWN database.
  #
  # Auth::Database.connection, not create_test_database: the latter is a
  # DIFFERENT database that the running app never reads, so the login would
  # fail with "no matching login" (401) and every example below would pass for
  # the wrong reason — a false green that hides exactly the gap this file
  # exists to prove.
  def create_account(email:)
    db = Auth::Database.connection
    id = db[:accounts].insert(
      email: email,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: SecureRandom.uuid,
      created_at: Time.now,
      updated_at: Time.now,
    )
    # Cost params match config/features/argon2.rb's test config.
    hasher = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    db[:account_password_hashes].insert(id: id, password_hash: hasher.create(password))
    email
  end

  # A host DomainStrategy will classify as :custom, in one of the SigninConfig
  # shapes under test.
  #
  # signin_config: nil          => NO SigninConfig row at all (case E — the
  #                                "never opted in" default, the common shape)
  #                a Hash       => attributes for a SigninConfig row
  # sso:           true         => also stand up tenant SSO credentials
  def build_domain(label, signin_config: nil, sso: false)
    owner = Onetime::Customer.new(email: "owner-#{label}-#{run_id}@test.local")
    owner.save
    org = Onetime::Organization.create!("SigninEnabled Org #{label} #{run_id}", owner, 'contact@test.local')

    # tr('_', '-'): an underscore is not a legal hostname label character and
    # DomainStrategy silently falls back to the canonical host for one, which
    # would make the example pass vacuously on the operator branch.
    host   = "signin-#{label.to_s.tr('_', '-')}-#{run_id}.example.com"
    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    if signin_config
      Onetime::CustomDomain::SigninConfig.create!(
        **{ domain_id: domain.identifier }.merge(signin_config),
      )
    end

    if sso
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: domain.identifier,
        provider_type: 'oidc',
        display_name: 'Tenant SSO',
        issuer: 'https://idp.example.com',
        client_id: "client-#{run_id}",
        client_secret: "secret-#{run_id}",
        enabled: true,
      )
    end

    @fixtures << [org, domain, owner, host]
    host
  end

  before { @fixtures = [] }

  after do
    Array(@fixtures).each do |org, domain, owner, host|
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain.display_domain_index.remove(host)
      domain.destroy!
      org.destroy!
      owner.destroy!
    rescue StandardError => ex
      warn "[signin_enabled spec] cleanup failed for #{host}: #{ex.message}"
    end
  end

  # POST with the CSRF token AND an explicit Host so DomainStrategy classifies
  # the request as the tenant under test. CSRF matters: check_csrf runs BEFORE
  # before_rodauth, so a token-less POST is rejected upstream of the gate and
  # the example would pass for the wrong reason.
  def post_as(host, path, params = {})
    header 'Host', host
    csrf_json_post(path, params)
  end

  # A gated route must be byte-identical to an undefined one
  # (ADR-034#reject-as-not-found-not-forbidden): same status AND the router's
  # shared ADR-013 body, not a bespoke shape.
  def expect_not_found(response, path)
    expect(response.status).to eq(404),
      "#{path} returned #{response.status}, expected 404. Body: #{response.body[0, 300]}"
    body = JSON.parse(response.body)
    expect(body['error_type']).to eq('NotFound'),
      "#{path} 404'd with a non-router body: #{response.body[0, 300]}"
  end

  def route_mounted?(path)
    Auth::Config.route_hash.key?(path)
  end

  # ==========================================================================
  # 1. THE REGRESSION CASES — a custom domain that never opted in
  # ==========================================================================
  #
  # Both used a VALID credential for a REAL verified account and returned 200 +
  # authenticated before Auth::SigninEnabled existed. Asserting with a valid
  # credential is the whole point: a nonexistent account 401s either way, which
  # proves only that the route is live, not that it is gated.
  #
  describe 'case D: an ENABLED SigninConfig with signin_enabled=false (explicit opt-OUT)' do
    let(:host) do
      build_domain(:opted_out, signin_config: {
        enabled: true,
        signin_enabled: false,
        sso_enabled: false,
      })
    end

    it '404s POST /auth/login for a VALID credential' do
      email = create_account(email: "user-d-#{run_id}@example.com")

      expect_not_found(post_as(host, '/auth/login', login: email, password: password), '/auth/login')
    end

    it '404s POST /auth/login for a nonexistent account too (no enumeration side channel)' do
      # The gate must fire BEFORE credential processing, so the two answers are
      # indistinguishable. A 401 here would leak that the route is live and
      # would also mean the gate is running too late to be an availability gate.
      expect_not_found(
        post_as(host, '/auth/login', login: "nobody-#{run_id}@example.com", password: password),
        '/auth/login',
      )
    end

    it '404s the secondary password endpoints' do
      # /auth/create-account is NOT in this list: registration answers to the
      # SIGN-UP opt-in (Auth::SignupEnabled, SignupConfig#signup_enabled), not
      # this gate — see signup_enabled_enforcement_spec.rb.
      %w[/auth/reset-password-request /auth/reset-password].each do |path|
        expect_not_found(post_as(host, path, login: "nobody-#{run_id}@example.com", password: password), path)
      end
    end

    it '404s POST /auth/email-auth-request (email_auth is the other half of the opt-in)' do
      skip 'email_auth feature not enabled in this lane' unless route_mounted?('/email-auth-request')

      expect_not_found(
        post_as(host, '/auth/email-auth-request', login: "nobody-#{run_id}@example.com"),
        '/auth/email-auth-request',
      )
    end
  end

  describe 'case E: NO SigninConfig at all (the "custom domains default OFF" case)' do
    let(:host) { build_domain(:no_config) }

    it '404s POST /auth/login for a VALID credential' do
      email = create_account(email: "user-e-#{run_id}@example.com")

      expect_not_found(post_as(host, '/auth/login', login: email, password: password), '/auth/login')
    end

    it '404s the secondary password endpoints' do
      %w[/auth/reset-password-request /auth/reset-password].each do |path|
        expect_not_found(post_as(host, path, login: "nobody-#{run_id}@example.com", password: password), path)
      end
    end
  end

  # ==========================================================================
  # 2. THE GATE NARROWS, IT DOES NOT CLOSE
  # ==========================================================================

  describe 'a domain that HAS opted in (enabled=true, signin_enabled=true)' do
    let(:host) do
      build_domain(:opted_in, signin_config: {
        enabled: true,
        signin_enabled: true,
        sso_enabled: false,
      })
    end

    it 'authenticates a valid credential at POST /auth/login' do
      email    = create_account(email: "user-in-#{run_id}@example.com")
      response = post_as(host, '/auth/login', login: email, password: password)

      expect(response.status).to eq(200),
        "an opted-in domain must still sign in (got #{response.status}: #{response.body[0, 300]})"
    end

    it 'leaves the secondary password endpoints reachable' do
      response = post_as(host, '/auth/reset-password-request', login: "nobody-#{run_id}@example.com")

      expect(response.status).not_to eq(404)
    end
  end

  describe 'canonical / operator hosts' do
    it 'classifies as :canonical (guards against a vacuous pass on :invalid)' do
      seen = nil
      allow(Auth::SigninEnabled).to receive(:enabled_for_request?).and_wrap_original do |orig, env|
        seen = env['onetime.domain_strategy']
        orig.call(env)
      end

      post_as(canonical_host, '/auth/login', login: "nobody-#{run_id}@example.com", password: password)
      expect(seen).to eq(:canonical)
    end

    it 'authenticates normally — operator defaults are untouched' do
      email    = create_account(email: "user-canon-#{run_id}@example.com")
      response = post_as(canonical_host, '/auth/login', login: email, password: password)

      expect(response.status).to eq(200),
        "the canonical host must follow the operator default (got #{response.status}: #{response.body[0, 300]})"
    end

    it 'leaves logout reachable' do
      expect(post_as(canonical_host, '/auth/logout').status).not_to eq(404)
    end
  end

  # ==========================================================================
  # 3. ROUTES THIS GATE MUST NOT TOUCH
  # ==========================================================================

  describe 'routes outside the password/email opt-in' do
    let(:host) do
      build_domain(:not_gated, signin_config: {
        enabled: true,
        signin_enabled: false,
        sso_enabled: true,
      }, sso: true)
    end

    it 'never gates logout — logout must never 404' do
      expect(post_as(host, '/auth/logout').status).not_to eq(404)
    end

    it 'never gates the SSO request phase on signin_enabled (#4139)' do
      skip 'SSO routes not registered in this lane' unless Onetime.auth_config.orgs_sso_enabled?

      # signin_enabled is the PASSWORD/EMAIL opt-in. An SSO-only tenant sets
      # signin_enabled=false precisely to say "no passwords here" — gating SSO
      # on it takes that tenant's only working sign-in path dark, which is the
      # #4139 regression verbatim.
      response = post_as(host, '/auth/sso/oidc')
      expect(response.status).not_to eq(404),
        'SSO must not be gated by signin_enabled (#4139)'
    end

    it 'never gates the second-factor ceremony routes' do
      # Second factors are a property of the ACCOUNT, not of the request host
      # (ADR-034#reject-as-not-found-not-forbidden "Scope"). Gating them on a
      # host flag is a lockout, not an access control.
      skip 'webauthn feature not enabled in this lane' unless route_mounted?('/webauthn-auth')

      expect(post_as(host, '/auth/webauthn-auth').status).not_to eq(404)
    end
  end

  # ==========================================================================
  # 4. POLICY-SOURCE CONTRACT
  # ==========================================================================
  #
  # These lock the two decisions that are easy to "simplify" away in a later
  # edit and would silently re-open the gap.
  #
  describe 'policy source (ADR-034#resolution-is-model-owned)' do
    it 'asks the model resolver rather than re-deriving availability locally' do
      expect(Onetime::CustomDomain::SigninConfig)
        .to receive(:resolve_signin_enabled_for_request)
        .at_least(:once)
        .and_return(true)

      post_as(build_domain(:probe), '/auth/login', login: "nobody-#{run_id}@example.com", password: password)
    end

    it 'omits domain_id, keeping the strict-false branch for the POST gate' do
      # Passing domain_id would enable the tenant-SSO DISPLAY carve-out
      # (signin_config.rb, resolve_signin_enabled_for_custom_domain), which
      # would let an SSO-only tenant's password POST through. SSO never flows
      # through this route, so the asymmetry is deliberate (#3415, #3783).
      allow(Onetime::CustomDomain::SigninConfig)
        .to receive(:resolve_signin_enabled_for_request)
        .and_wrap_original do |orig, *args, **kwargs|
          expect(kwargs).not_to have_key(:domain_id)
          orig.call(*args, **kwargs)
        end

      post_as(build_domain(:no_domain_id), '/auth/login', login: "nobody-#{run_id}@example.com", password: password)
    end

    it 'gates the password and email_auth pre-auth routes, minus the account-creation ceremony' do
      # Reuses Auth::RestrictTo's classification rather than a second copy of
      # it, so a newly-classified route cannot be covered by one gate and
      # missed by the other. The account-creation routes answer to the SIGN-UP
      # opt-in and are owned by Auth::SignupEnabled instead — gating them here
      # 404'd an SSO-only tenant's open registration (signin_enabled=false,
      # signup_enabled=true).
      expected = Auth::RestrictTo::PRE_AUTH_ROUTES
                 .select { |_, m| %w[password email_auth].include?(m) }
                 .keys - Auth::SignupEnabled::GATED_ROUTES

      expect(Auth::SigninEnabled::GATED_ROUTES.to_a).to match_array(expected)

      expect(Auth::SigninEnabled::GATED_ROUTES).not_to include(:logout)
      expect(Auth::SigninEnabled::GATED_ROUTES).not_to include(*Auth::RestrictTo::SECOND_FACTOR_ROUTES.keys)
      expect(Auth::SigninEnabled::GATED_ROUTES).not_to include(:webauthn_login)
    end

    it 'partitions the password/email pre-auth routes with Auth::SignupEnabled — disjoint, jointly exhaustive' do
      # Every password/email pre-auth route is claimed by exactly ONE
      # availability gate. A route in both would let the sign-in opt-in veto
      # registration again; a route in neither is the original full-mode gap.
      password_email = Auth::RestrictTo::PRE_AUTH_ROUTES
                       .select { |_, m| %w[password email_auth].include?(m) }
                       .keys

      expect(Auth::SigninEnabled::GATED_ROUTES & Auth::SignupEnabled::GATED_ROUTES).to be_empty
      expect(Auth::SigninEnabled::GATED_ROUTES.to_a + Auth::SignupEnabled::GATED_ROUTES.to_a)
        .to match_array(password_email)
    end
  end
end
