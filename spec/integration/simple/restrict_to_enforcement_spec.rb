# spec/integration/simple/restrict_to_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — restrict_to enforcement in SIMPLE mode (#4139)
# =============================================================================
#
# The SIMPLE-mode half of ADR-024 A1. In simple mode POST /auth/login is served
# by Core::Controllers::Authentication (apps/web/core/routes.txt), NOT by
# Rodauth, so the before_rodauth gate in
# apps/web/auth/config/hooks/restrict_to.rb never runs for it. Without the
# Core-side gate (Core::Controllers::Base#restrict_to_allows?) enforcement
# would be mode-dependent — present in full mode, absent in simple — which is
# the shape A7 warns about: enforcement that looks closed and is not.
#
# The FULL-mode half is
# apps/web/auth/spec/integration/full/restrict_to_enforcement_spec.rb. Neither
# spec's assertions transfer to the other mode, hence the skip guard below.
#
# Note what is actually under test here: AuthConfig#restrict_to returns nil
# unless full_enabled?, so in simple mode the only restriction that can speak
# is a PER-DOMAIN one on a custom domain that has opted into sign-in. That is
# also the only shape a customer can configure without operator access.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=simple
#
# RUN:
#   tests/lanes/run simple
#   # or directly:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
#     spec/integration/simple/restrict_to_enforcement_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'

RSpec.describe 'restrict_to enforcement — simple mode (ADR-024 A1/A7, #4139)', type: :integration do
  include Rack::Test::Methods

  # Memoized: repeated generate_rack_url_map calls corrupt middleware state.
  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
    app

    # The custom-domain feature ships OFF in the test config (DOMAINS_ENABLED),
    # and with it off Onetime::Middleware::DomainStrategy classifies every
    # request :canonical and reports the canonical host as
    # env['onetime.display_domain'] — so the per-domain SigninConfig is never
    # reached and every example here would pass vacuously. Flip the runtime
    # flag (not the env var — the lane env is shared) and restore after.
    @original_features        = Onetime::Runtime.features
    Onetime::Runtime.features = @original_features.with(domains_enabled: true)
  end

  after(:all) do
    Onetime::Runtime.features = @original_features if @original_features
  end

  before do
    skip 'requires simple auth mode' if Onetime.auth_config.full_enabled?

    @fixtures = []
  end

  after do
    Array(@fixtures).each do |org, domain, owner, host|
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain::SignupConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain.display_domain_index.remove(host)
      domain.destroy!
      org.destroy!
      owner.destroy!
    rescue StandardError => ex
      warn "[restrict_to simple spec] cleanup failed for #{host}: #{ex.message}"
    end
  end

  let(:run_id) { SecureRandom.hex(6) }

  # A custom domain with sign-in explicitly opted in (signin_enabled), so
  # Base#signin_enabled? passes and the ONLY thing that can reject the POST is
  # the restrict_to gate. Without signin_enabled the example would pass for the
  # wrong reason: custom domains default sign-in OFF.
  # Sign-UP is opted in for the same reason sign-in is: custom domains default
  # sign-up OFF, so without an enabled SignupConfig the create-account examples
  # would 302 out of Base#signup_enabled? before the restrict_to gate is
  # reached and pass for the wrong reason.
  def build_restricted_domain(restrict_to)
    label = restrict_to.nil? ? 'unrestricted' : restrict_to.tr('_', '-')
    owner = Onetime::Customer.new(email: "owner-#{label}-#{run_id}@test.local")
    owner.save
    org  = Onetime::Organization.create!("RestrictTo Simple #{label} #{run_id}", owner, 'contact@test.local')
    # tr('_', '-'): an underscore is not legal in a hostname label and
    # DomainStrategy falls back to the canonical host for one, which would
    # make the example pass vacuously.
    host = "simple-#{label}-#{run_id}.example.com"

    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    signin_attrs = { domain_id: domain.identifier, enabled: true, signin_enabled: true }
    signin_attrs[:restrict_to] = restrict_to unless restrict_to.nil?
    Onetime::CustomDomain::SigninConfig.create!(**signin_attrs)

    Onetime::CustomDomain::SignupConfig.create!(
      domain_id: domain.identifier,
      enabled: true,
      signup_enabled: true,
      validation_strategy: 'passthrough',
    )

    @fixtures << [org, domain, owner, host]
    host
  end

  # Fresh session + CSRF token, then the crafted POST. A silently-nil shrimp
  # draws a 403 from the CSRF middleware and would surface as a misleading
  # status assertion, so setup failure is loud.
  def post_json(host, path, payload)
    clear_cookies
    header 'Host', host
    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/'
    token = last_response.headers['X-CSRF-Token']

    raise "CSRF setup failed: GET / returned #{last_response.status} with no X-CSRF-Token" if token.to_s.empty?

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token
    post path, JSON.generate(payload.merge(shrimp: token))

    if last_response.status == 403
      raise "CSRF rejected by the stack (403): #{last_response.body}. " \
            'This is a session/middleware problem, not a restrict_to result.'
    end

    last_response
  end

  def post_login(host, login: 'nobody@example.com', password: 'integration-test-pw')
    post_json(host, '/auth/login', { login: login, password: password })
  end

  # The three additional pre-auth password surfaces simple mode serves from
  # Core::Controllers::Registration (ADR-024 A7, "pre-auth password surfaces
  # are not exempt"). Payloads are deliberately plausible-but-doomed: the gate
  # must fire before any of them can be evaluated.
  def post_create_account(host)
    post_json(host, '/auth/create-account', {
      email: "newbie-#{SecureRandom.hex(4)}@test.local",
      password: 'integration-test-pw',
      password2: 'integration-test-pw',
    })
  end

  def post_reset_password_request(host)
    post_json(host, '/auth/reset-password-request', { email: 'nobody@example.com' })
  end

  # A plain `status == 404` check is not a safe discriminator for
  # /auth/reset-password: its own MissingSecret rescue ALSO answers 404 (an
  # invalid token is a legitimate not-found). The gate's 404 is the one carrying
  # RecordNotFound's serialized shape, so match on that instead — otherwise the
  # "permitted host still works" example would pass while the gate was rejecting
  # everything.
  def gate_rejected?(response)
    return false unless response.status == 404

    body = JSON.parse(response.body)
    body['error_type'] == 'RecordNotFound' && body['error'] == 'Not Found'
  rescue JSON::ParserError
    false
  end

  def post_reset_password(host)
    post_json(host, '/auth/reset-password', {
      key: SecureRandom.hex(16),
      newp: 'integration-test-pw',
      newp2: 'integration-test-pw',
    })
  end

  it "404s POST /auth/login on a host restricted to 'sso'" do
    response = post_login(build_restricted_domain('sso'))

    expect(response.status).to eq(404),
      "expected the password route to read as undefined on an sso-restricted host " \
      "(ADR-024 A7), got #{response.status}: #{response.body[0, 300]}"
  end

  it "404s POST /auth/login on a host restricted to 'email_auth'" do
    response = post_login(build_restricted_domain('email_auth'))

    expect(response.status).to eq(404), "got #{response.status}: #{response.body[0, 300]}"
  end

  it "404s POST /auth/login on a host whose restriction is :unavailable" do
    # 'webauthn' cannot be honored on a custom domain (#4137), so resolution is
    # :unavailable — fail CLOSED, never widening back to the password form.
    response = post_login(build_restricted_domain('webauthn'))

    expect(response.status).to eq(404), "got #{response.status}: #{response.body[0, 300]}"
  end

  it "does NOT reject on a host restricted to 'password'" do
    response = post_login(build_restricted_domain('password'))

    # A bad credential (4xx that is not 404) is the healthy answer. 404 would
    # mean the gate rejects the very method the host permits.
    expect(response.status).not_to eq(404),
      'the permitted method must stay reachable on its own restricted host'
  end

  it 'does NOT reject POST /auth/login on an unrestricted host' do
    response = post_login(build_restricted_domain(nil))

    expect(response.status).not_to eq(404),
      'a domain with no restrict_to must be unaffected by the gate'
  end

  # ---------------------------------------------------------------------------
  # An UNREADABLE policy (#4139). The per-domain half of restrict_to is a
  # datastore read; when it fails the gate does not know what this host permits
  # and must not guess. What it must NOT do is answer with the gate's own 404:
  # that shape is built to be indistinguishable from an undefined route, so a
  # blip would read as a routing regression on an install that may restrict
  # nothing. 503 is the honest, alertable answer — and it is what makes
  # unconditional fail-closed survivable.
  # ---------------------------------------------------------------------------
  describe 'when the host policy cannot be read' do
    it '503s POST /auth/login on a custom host, not 404' do
      host = build_restricted_domain('password')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .and_raise(Redis::BaseError, 'datastore unavailable')

      response = post_login(host)

      expect(response.status).to eq(503),
        "expected an unreadable policy to answer 503, got #{response.status}: #{response.body[0, 300]}"

      body = JSON.parse(response.body)
      expect(body['error_type']).to eq('SigninPolicyUnavailable')
      expect(response.headers['retry-after']).to eq(Onetime::SigninPolicyUnavailable::RETRY_AFTER.to_s)
    end

    it 'does not fail an operator host — its restriction is in-memory and still known' do
      # domains_enabled OFF for this example only: with it on, DomainStrategy
      # classifies the test canonical host (an IP:port, which PublicSuffix
      # rejects) :invalid, and :invalid fails closed by design. Off is also the
      # honest shape of the case under test — an install with no custom domains
      # has nothing per-domain to lose when a datastore read fails.
      features                  = Onetime::Runtime.features
      Onetime::Runtime.features = features.with(domains_enabled: false)
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .and_raise(Redis::BaseError, 'datastore unavailable')

      response = post_login(Onetime::Middleware::DomainStrategy.canonical_domain)

      expect(response.status).not_to eq(503),
        'an operator host has no per-domain half to lose and must stay reachable'
    ensure
      Onetime::Runtime.features = features if features
    end
  end

  # ---------------------------------------------------------------------------
  # The other three pre-auth password surfaces (#4139, ADR-024 A7).
  #
  # These are served by Core::Controllers::Registration in simple mode and were
  # ungated when the login gate landed, so enforcement was endpoint-dependent
  # inside simple mode as well as mode-dependent between modes. A7 names all
  # three explicitly as NOT exempt.
  # ---------------------------------------------------------------------------
  {
    'POST /auth/create-account'          => :post_create_account,
    'POST /auth/reset-password-request'  => :post_reset_password_request,
    'POST /auth/reset-password'          => :post_reset_password,
  }.each do |description, verb|
    describe description do
      it "404s on a host restricted to 'sso'" do
        response = send(verb, build_restricted_domain('sso'))

        expect(gate_rejected?(response)).to be(true),
          "expected #{description} to read as undefined on an sso-restricted host " \
          "(ADR-024 A7), got #{response.status}: #{response.body[0, 300]}"
      end

      it "404s on a host restricted to 'email_auth'" do
        response = send(verb, build_restricted_domain('email_auth'))

        expect(gate_rejected?(response)).to be(true), "got #{response.status}: #{response.body[0, 300]}"
      end

      it '404s on a host whose restriction resolves to :unavailable' do
        # 'webauthn' cannot be honored on a custom domain (#4137), so resolution
        # is :unavailable — fail CLOSED, never widening back to password.
        response = send(verb, build_restricted_domain('webauthn'))

        expect(gate_rejected?(response)).to be(true), "got #{response.status}: #{response.body[0, 300]}"
      end

      it "does NOT reject on a host restricted to 'password'" do
        response = send(verb, build_restricted_domain('password'))

        expect(gate_rejected?(response)).to be(false),
          'the permitted method must stay reachable on its own restricted host'
      end

      it 'does NOT reject on an unrestricted host' do
        response = send(verb, build_restricted_domain(nil))

        expect(gate_rejected?(response)).to be(false),
          'a domain with no restrict_to must be unaffected by the gate'
      end
    end
  end
end
