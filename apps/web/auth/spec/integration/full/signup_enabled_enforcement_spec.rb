# apps/web/auth/spec/integration/full/signup_enabled_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — per-domain `signup_enabled` as an AVAILABILITY GATE
# on the full-mode account-creation routes
# (ADR-024 "custom domains default OFF, opt-in only";
#  ADR-034#reject-as-not-found-not-forbidden for the reject shape)
# =============================================================================
#
# TWO GAPS, ONE FILE
#
# 1. THE OVER-GATE (the headline regression case below). An early draft of the
#    full-mode availability gate inherited PRE_AUTH_ROUTES' 'password'
#    classification wholesale, so create_account / verify_account /
#    verify_account_resend were gated on the SIGN-IN opt-in
#    (SigninConfig#signin_enabled). On an SSO-only tenant with open
#    registration — SigninConfig signin_enabled=false, SignupConfig
#    signup_enabled=true, a real and reasonable shape — POST
#    /auth/create-account went from 200 "Your account has been created" to
#    404, killed by a policy the domain owner never applied to registration.
#    Verified by execution before the fix.
#
# 2. THE UNDER-GATE. Symmetrically, nothing in full mode consulted the
#    per-domain SIGN-UP opt-in at all. ADR-024's default-OFF promise for
#    custom domains was enforced for signup in simple mode
#    (Core::Controllers::Base#signup_enabled?) and nowhere on the Rodauth
#    routes, so a custom domain that never opted into registration still
#    created accounts at POST /auth/create-account.
#
# Both close the same way: the account-creation ceremony is owned by
# Auth::SignupEnabled (against SignupConfig's model resolver) and subtracted
# from Auth::SigninEnabled's route set — each route claimed by exactly one
# availability gate.
#
# REQUIREMENTS / RUN: same as signin_enabled_enforcement_spec.rb —
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     ORGS_SSO_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/signup_enabled_enforcement_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'per-domain signup_enabled enforcement — full mode (ADR-024 custom domains default OFF)',
  type: :integration do
  include Rack::Test::Methods

  before(:all) do
    boot_onetime_app

    # Same lane surgery as signin_enabled_enforcement_spec.rb, for the same
    # reasons documented there at length: DOMAINS_ENABLED must be on or every
    # request classifies :canonical (vacuous pass), and site.host must be
    # replaced by a PublicSuffix-parseable canonical host or every non-custom
    # host classifies :invalid (operator examples untestable).
    @original_features        = Onetime::Runtime.features
    Onetime::Runtime.features = @original_features.with(domains_enabled: true)

    @original_domains_config       = OT.conf.dig('features', 'domains') || {}
    OT.conf['features']['domains'] = @original_domains_config.merge(
      'enabled' => true,
      'default' => CANONICAL_HOST,
    )
    Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
  end

  after(:all) do
    Onetime::Runtime.features = @original_features if @original_features
    if @original_domains_config
      OT.conf['features']['domains'] = @original_domains_config
      Onetime::Middleware::DomainStrategy.initialize_from_config(@original_domains_config)
    end
  end

  CANONICAL_HOST = 'operator-signup-gate.example.com'

  let(:run_id)   { SecureRandom.hex(6) }
  let(:password) { 'TestPassword123!' }

  # A host DomainStrategy will classify as :custom, in one of the config
  # shapes under test. Either config hash may be nil (no row at all — the
  # default shape for both models).
  def build_domain(label, signin_config: nil, signup_config: nil)
    owner = Onetime::Customer.new(email: "owner-#{label}-#{run_id}@test.local")
    owner.save
    org = Onetime::Organization.create!("SignupEnabled Org #{label} #{run_id}", owner, 'contact@test.local')

    host   = "signup-#{label.to_s.tr('_', '-')}-#{run_id}.example.com"
    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    if signin_config
      Onetime::CustomDomain::SigninConfig.create!(
        **{ domain_id: domain.identifier }.merge(signin_config),
      )
    end

    if signup_config
      Onetime::CustomDomain::SignupConfig.create!(
        **{ domain_id: domain.identifier }.merge(signup_config),
      )
    end

    @fixtures << [org, domain, owner, host]
    host
  end

  before { @fixtures = [] }

  after do
    Array(@fixtures).each do |org, domain, owner, host|
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain::SignupConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain.display_domain_index.remove(host)
      domain.destroy!
      org.destroy!
      owner.destroy!
    rescue StandardError => ex
      warn "[signup_enabled spec] cleanup failed for #{host}: #{ex.message}"
    end
  end

  def post_as(host, path, params = {})
    header 'Host', host
    csrf_json_post(path, params)
  end

  # A WELL-FORMED create-account body. login-confirm matters: without it
  # Rodauth answers 422 "logins do not match" and a would-be 200 is
  # indistinguishable from a gate — the false negative that nearly hid the
  # over-gate regression when it was first probed.
  def signup_params(email)
    {
      login: email,
      'login-confirm': email,
      password: password,
      'password-confirm': password,
    }
  end

  def expect_not_found(response, path)
    expect(response.status).to eq(404),
      "#{path} returned #{response.status}, expected 404. Body: #{response.body[0, 300]}"
    body = JSON.parse(response.body)
    expect(body['error_type']).to eq('NotFound'),
      "#{path} 404'd with a non-router body: #{response.body[0, 300]}"
  end

  # ==========================================================================
  # 1. THE OVER-GATE REGRESSION — sign-in opt-out must not veto registration
  # ==========================================================================

  describe 'SSO-only sign-in with OPEN registration (signin_enabled=false, signup_enabled=true)' do
    let(:host) do
      build_domain(:sso_open_reg,
        signin_config: { enabled: true, signin_enabled: false, sso_enabled: true },
        signup_config: { enabled: true, signup_enabled: true },)
    end

    it 'creates an account at POST /auth/create-account (200, not 404)' do
      response = post_as(host, '/auth/create-account', signup_params("newuser-#{run_id}@example.com"))

      expect(response.status).to eq(200),
        "an opted-in registration must succeed regardless of the SIGN-IN opt-out " \
        "(got #{response.status}: #{response.body[0, 300]})"
      expect(JSON.parse(response.body)['success']).to match(/created/i)
    end

    it 'still 404s POST /auth/login — the sign-in opt-out keeps its own routes' do
      expect_not_found(
        post_as(host, '/auth/login', login: "nobody-#{run_id}@example.com", password: password),
        '/auth/login',
      )
    end
  end

  # ==========================================================================
  # 2. THE UNDER-GATE — custom domains default OFF for registration too
  # ==========================================================================
  #
  # All three closed shapes assert with a WELL-FORMED body for the same reason
  # the sign-in spec uses a valid credential: a malformed request fails either
  # way and proves only that the route is live.
  #
  describe 'NO SignupConfig at all (the "never opted in" default shape)' do
    let(:host) { build_domain(:no_config) }

    it '404s POST /auth/create-account' do
      expect_not_found(
        post_as(host, '/auth/create-account', signup_params("nobody-#{run_id}@example.com")),
        '/auth/create-account',
      )
    end

    it '404s the verification ceremony routes' do
      %w[/auth/verify-account /auth/verify-account-resend].each do |path|
        expect_not_found(post_as(host, path, login: "nobody-#{run_id}@example.com"), path)
      end
    end
  end

  describe 'an ENABLED SignupConfig with signup_enabled=false (explicit opt-OUT)' do
    let(:host) do
      build_domain(:opted_out, signup_config: { enabled: true, signup_enabled: false })
    end

    it '404s POST /auth/create-account' do
      expect_not_found(
        post_as(host, '/auth/create-account', signup_params("nobody-#{run_id}@example.com")),
        '/auth/create-account',
      )
    end
  end

  describe 'a SignupConfig whose master switch is OFF (enabled=false, signup_enabled=true)' do
    let(:host) do
      # A disabled config expresses no opinion, and custom domains default
      # OFF — same rule as the sign-in side (resolve_*_for_custom_domain).
      build_domain(:master_off, signup_config: { enabled: false, signup_enabled: true })
    end

    it '404s POST /auth/create-account' do
      expect_not_found(
        post_as(host, '/auth/create-account', signup_params("nobody-#{run_id}@example.com")),
        '/auth/create-account',
      )
    end
  end

  # ==========================================================================
  # 3. THE GATE NARROWS, IT DOES NOT CLOSE
  # ==========================================================================

  describe 'canonical / operator hosts' do
    it 'classifies as :canonical (guards against a vacuous pass on :invalid)' do
      seen = nil
      allow(Auth::SignupEnabled).to receive(:enabled_for_request?).and_wrap_original do |orig, env|
        seen = env['onetime.domain_strategy']
        orig.call(env)
      end

      post_as(CANONICAL_HOST, '/auth/create-account', signup_params("probe-#{run_id}@example.com"))
      expect(seen).to eq(:canonical)
    end

    it 'creates accounts per the operator default — untouched by the per-domain gate' do
      response = post_as(CANONICAL_HOST, '/auth/create-account', signup_params("canon-#{run_id}@example.com"))

      expect(response.status).to eq(200),
        "the canonical host must follow the operator default (got #{response.status}: #{response.body[0, 300]})"
    end
  end

  describe 'routes outside the signup opt-in' do
    let(:host) do
      build_domain(:not_gated, signup_config: { enabled: true, signup_enabled: false })
    end

    it 'never gates logout' do
      expect(post_as(host, '/auth/logout').status).not_to eq(404)
    end

    it 'does not gate the sign-in routes — signup opt-out is not a sign-in opt-out' do
      # No SigninConfig on this domain, so sign-in 404s here too — but by the
      # SIGN-IN gate. Prove the axis by asserting the SIGNUP gate never ran
      # for the login route.
      expect(Auth::SignupEnabled).not_to receive(:enforce!)

      post_as(host, '/auth/login', login: "nobody-#{run_id}@example.com", password: password)
    end
  end

  # ==========================================================================
  # 4. POLICY-SOURCE CONTRACT
  # ==========================================================================

  describe 'policy source (ADR-034#resolution-is-model-owned)' do
    it 'asks the model resolver rather than re-deriving availability locally' do
      expect(Onetime::CustomDomain::SignupConfig)
        .to receive(:resolve_signup_enabled_for_request)
        .at_least(:once)
        .and_return(true)

      post_as(build_domain(:probe), '/auth/create-account', signup_params("probe2-#{run_id}@example.com"))
    end

    it 'gates exactly the account-creation ceremony' do
      expect(Auth::SignupEnabled::GATED_ROUTES.to_a)
        .to match_array(%i[create_account verify_account verify_account_resend])
    end
  end
end
