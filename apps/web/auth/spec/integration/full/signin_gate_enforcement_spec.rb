# apps/web/auth/spec/integration/full/signin_gate_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — the sign-in / sign-up OPT-IN axis as an ACCESS
# CONTROL in full mode (ADR-024, ADR-034#reject-as-not-found-not-forbidden,
# #4163)
# =============================================================================
#
# THE DEFECT. Simple mode consults the ADR-024 resolvers at its POST handlers;
# full mode did not. A custom domain with no enabled SigninConfig — a host
# whose /signin page offers nothing and whose masthead hides the link — still
# ACCEPTED POST /auth/login and authenticated canonical accounts, because
# Rodauth serves that route and only the `restrict_to` axis was gated
# (restrict_to_enforcement_spec.rb, its sibling in this directory). These
# examples are the crafted POSTs.
#
# THE TWO AXES ARE SEPARATED ON PURPOSE HERE. Both reject as the same 404, so
# an example that merely asserts 404 on a host with no configuration at all
# would pass whichever gate fired. The isolating cases are the ones in the
# middle: a host with an enabled SigninConfig (which makes the restrict_to
# resolution :unrestricted, so that gate cannot be the one rejecting) and NO
# SignupConfig, where the 404 on /auth/create-account can only be this gate —
# and its mirror image.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   tests/lanes/run full-sqlite
#   # or directly:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     ORGS_SSO_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/signin_gate_enforcement_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'sign-in/sign-up opt-in enforcement — full mode (ADR-024, #4163)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    boot_onetime_app

    # The custom-domain feature ships OFF in the test config (DOMAINS_ENABLED),
    # and with it off Onetime::Middleware::DomainStrategy short-circuits: every
    # request is classified :canonical and env['onetime.display_domain'] is the
    # canonical host, so a per-domain config can never be reached and every
    # example here would pass vacuously against the operator default. Flip the
    # runtime flag (not the env var — the lane env is shared) and restore after.
    @original_features        = Onetime::Runtime.features
    Onetime::Runtime.features = @original_features.with(domains_enabled: true)
  end

  after(:all) do
    Onetime::Runtime.features = @original_features if @original_features
  end

  let(:run_id) { SecureRandom.hex(6) }

  # A host DomainStrategy will classify as :custom, with whichever per-domain
  # opt-in records the example needs and nothing else.
  #
  # tr('_', '-'): an underscore is not legal in a hostname label, and
  # DomainStrategy silently falls back to the canonical host for one
  # (basically_valid? fails), which would make the example pass vacuously.
  def build_domain(label, signin: nil, signup: nil)
    owner = Onetime::Customer.new(email: "owner-#{run_id}@test.local")
    owner.save
    org  = Onetime::Organization.create!("SigninGate Org #{run_id}", owner, 'contact@test.local')
    host = "optin-#{label.tr('_', '-')}-#{run_id}.example.com"

    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    # restrict_to is left unset on purpose: this file is about the OTHER axis,
    # and an enabled SigninConfig with no restriction resolves :unrestricted, so
    # Auth::RestrictTo cannot be the gate producing any 404 below.
    unless signin.nil?
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: domain.identifier,
        enabled: true,
        signin_enabled: signin,
        sso_enabled: false,
      )
    end

    unless signup.nil?
      Onetime::CustomDomain::SignupConfig.create!(
        domain_id: domain.identifier,
        enabled: true,
        signup_enabled: signup,
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
      warn "[signin_gate spec] cleanup failed for #{host}: #{ex.message}"
    end
  end

  # POST with the CSRF token AND an explicit Host, so DomainStrategy classifies
  # the request as the tenant under test. CSRF matters: check_csrf runs BEFORE
  # before_rodauth, so a token-less POST would be rejected upstream of the gate
  # and the example would pass for the wrong reason.
  def post_as(host, path, params = {})
    header 'Host', host
    csrf_json_post(path, params)
  end

  def login_params
    { login: "nobody-#{run_id}@example.com", password: 'x' * 20 }
  end

  def signup_params
    { login: "newbie-#{run_id}@example.com", password: 'x' * 20, 'password-confirm': 'x' * 20 }
  end

  # A gated route must be byte-identical to an undefined one
  # (ADR-034#reject-as-not-found-not-forbidden): same status AND the router's
  # shared ADR-013 body, not a bespoke shape.
  def expect_not_found(response, path)
    expect(response.status).to eq(404),
      "#{path} returned #{response.status}, expected 404 (the host never opted in). " \
      "Body: #{response.body[0, 300]}"
    expect(JSON.parse(response.body)['error_type']).to eq('NotFound'),
      "#{path} 404'd with a non-router body: #{response.body[0, 300]}"
  end

  # The route RAN. 401 (no such account) is the healthy answer for a crafted
  # login; what matters is that the gate did not stand in front of it.
  def expect_route_executed(response, path)
    expect(response.status).not_to eq(404),
      "#{path} was rejected on a host that opted in (got 404)"
  end

  def route_mounted?(path)
    Auth::Config.route_hash.key?(path)
  end

  # ==========================================================================
  # 1. The defect: a custom host that opted into nothing
  # ==========================================================================

  describe 'a custom host with NO per-domain opt-in' do
    let(:host) { build_domain('none') }

    it '404s POST /auth/login — this is the #4163 defect' do
      expect_not_found(post_as(host, '/auth/login', login_params), '/auth/login')
    end

    it '404s POST /auth/create-account' do
      expect_not_found(post_as(host, '/auth/create-account', signup_params), '/auth/create-account')
    end

    # Password recovery is a sign-in path: the credential it mints is usable on
    # the canonical host, so leaving it open would make the opt-in advisory.
    it '404s POST /auth/reset-password-request' do
      expect_not_found(
        post_as(host, '/auth/reset-password-request', login: "nobody-#{run_id}@example.com"),
        '/auth/reset-password-request',
      )
    end

    it '404s POST /auth/email-auth-request' do
      skip 'email_auth feature not enabled in this lane' unless route_mounted?('/email-auth-request')

      expect_not_found(
        post_as(host, '/auth/email-auth-request', login: "nobody-#{run_id}@example.com"),
        '/auth/email-auth-request',
      )
    end

    # Exempt: gating logout would strand a signed-in user the moment a domain
    # owner flipped the opt-in off.
    it 'leaves logout reachable' do
      expect_route_executed(post_as(host, '/auth/logout'), '/auth/logout')
    end
  end

  # ==========================================================================
  # 2. The isolating cases — proof that THIS gate is the one firing
  # ==========================================================================
  #
  # Both gates reject as the same 404, so section 1 alone cannot tell them
  # apart. Here each host carries an enabled SigninConfig with no restrict_to,
  # which resolves :unrestricted — Auth::RestrictTo allows everything, and every
  # 404 below is necessarily the opt-in axis.
  #
  describe 'a custom host that opted into SIGN-IN only' do
    let(:host) { build_domain('signin-only', signin: true) }

    it 'executes POST /auth/login — the lookup ran and said yes' do
      expect_route_executed(post_as(host, '/auth/login', login_params), '/auth/login')
    end

    it 'still 404s POST /auth/create-account — sign-in does not imply sign-up' do
      expect_not_found(post_as(host, '/auth/create-account', signup_params), '/auth/create-account')
    end

    it 'executes POST /auth/reset-password-request' do
      expect_route_executed(
        post_as(host, '/auth/reset-password-request', login: "nobody-#{run_id}@example.com"),
        '/auth/reset-password-request',
      )
    end
  end

  describe 'a custom host that opted into SIGN-UP only' do
    # signin: false is an EXPLICIT opt-out on an enabled record, which is what
    # keeps the restrict_to axis unrestricted while this axis closes sign-in.
    let(:host) { build_domain('signup-only', signin: false, signup: true) }

    it 'executes POST /auth/create-account' do
      expect_route_executed(post_as(host, '/auth/create-account', signup_params), '/auth/create-account')
    end

    it '404s POST /auth/login — sign-up does not imply sign-in' do
      expect_not_found(post_as(host, '/auth/login', login_params), '/auth/login')
    end
  end

  describe 'a custom host whose enabled records opted OUT of both' do
    let(:host) { build_domain('opted-out', signin: false, signup: false) }

    it '404s both POSTs' do
      expect_not_found(post_as(host, '/auth/login', login_params), '/auth/login')
      expect_not_found(post_as(host, '/auth/create-account', signup_params), '/auth/create-account')
    end
  end

  # ==========================================================================
  # 3. The operator's own host is untouched
  # ==========================================================================

  describe 'the canonical host' do
    # THE CUSTOM-DOMAIN FEATURE GOES BACK OFF for this section, which is a
    # default install and the operator-host shape these examples are about:
    # DomainStrategy short-circuits and classifies every request :canonical.
    #
    # It has to be turned off explicitly, and that is not a test convenience.
    # This lane's canonical host is an IP:port, which is not a classifiable
    # domain — with the feature ON, DomainStrategy answers :invalid for it and
    # the gate takes the tenant-safe default-OFF branch, exactly as
    # ADR-024#operator-defaults-require-positive-classification requires. Correct
    # behavior, wrong subject: it would exercise the fail-closed branch again
    # rather than the operator default. Simple mode answers :invalid identically
    # (Core::Controllers::Base#signin_enabled? asks the same resolver), so this
    # is a property of the host, not a mode difference.
    around do |example|
      saved                     = Onetime::Runtime.features
      Onetime::Runtime.features = saved.with(domains_enabled: false)
      example.run
      Onetime::Runtime.features = saved
    end

    let(:canonical_host) do
      Onetime::Middleware::DomainStrategy.canonical_domain || 'localhost:3000'
    end

    it 'executes POST /auth/login' do
      skip 'sign-in disabled globally in this lane' unless
        Onetime::CustomDomain::SigninConfig.global_signin_enabled

      expect_route_executed(post_as(canonical_host, '/auth/login', login_params), '/auth/login')
    end

    it 'executes POST /auth/create-account' do
      skip 'sign-up disabled globally in this lane' unless
        Onetime::CustomDomain::SignupConfig.global_signup_enabled

      expect_route_executed(post_as(canonical_host, '/auth/create-account', signup_params),
        '/auth/create-account')
    end

    it 'leaves logout reachable' do
      expect_route_executed(post_as(canonical_host, '/auth/logout'), '/auth/logout')
    end
  end

  # ==========================================================================
  # 4. Route coverage — the guard against a new route slipping past the gate
  # ==========================================================================
  #
  # Rodauth freezes route_hash in post_configure, so this reads the LIVE mounted
  # set rather than a transcription of it. A new auth route either lands on this
  # axis (SIGNIN_ROUTES / SIGNUP_ROUTES) or gets an explicit exemption;
  # defaulting to "allowed" silently is the defect #4163 exists to close.
  #
  describe 'route coverage on the opt-in axis' do
    let(:gate) { Auth::SigninGate }

    def mounted_route_names
      Auth::Config.route_hash.values.map { |meth| meth.to_s.delete_prefix('handle_').to_sym }
    end

    it 'classifies every mounted Rodauth route as gated or explicitly exempt' do
      classified   = gate::GATED_ROUTES + gate::UNGATED_ROUTES
      unclassified = mounted_route_names - classified

      expect(unclassified).to be_empty,
        "Rodauth routes with no sign-in/sign-up opt-in classification: #{unclassified.inspect}\n" \
        'Add each to SIGNIN_ROUTES / SIGNUP_ROUTES or UNGATED_ROUTES (with a reason) ' \
        'in apps/web/auth/signin_gate.rb. See ADR-024.'
    end

    it 'reads a non-trivial route set (guards against a vacuous pass)' do
      expect(mounted_route_names).to include(:login, :logout)
      expect(mounted_route_names.size).to be >= 8
    end

    it 'never gates logout' do
      expect(gate::GATED_ROUTES).not_to include(:logout)
    end

    # The two axes must stay reject-identical, or the shape leaks which policy
    # closed the route.
    it 'rejects with the same body as the restrict_to gate' do
      expect(gate.not_found_response).to eq(Auth::RestrictTo.not_found_response)
    end
  end
end
