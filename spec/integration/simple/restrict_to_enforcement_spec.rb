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
  def build_restricted_domain(restrict_to)
    owner = Onetime::Customer.new(email: "owner-#{run_id}@test.local")
    owner.save
    org  = Onetime::Organization.create!("RestrictTo Simple #{run_id}", owner, 'contact@test.local')
    # tr('_', '-'): an underscore is not legal in a hostname label and
    # DomainStrategy falls back to the canonical host for one, which would
    # make the example pass vacuously.
    host = "simple-#{restrict_to.tr('_', '-')}-#{run_id}.example.com"

    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: domain.identifier,
      enabled: true,
      signin_enabled: true,
      restrict_to: restrict_to,
    )

    @fixtures << [org, domain, owner, host]
    host
  end

  # Fresh session + CSRF token, then the crafted POST. A silently-nil shrimp
  # draws a 403 from the CSRF middleware and would surface as a misleading
  # status assertion, so setup failure is loud.
  def post_login(host, login: 'nobody@example.com', password: 'integration-test-pw')
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
    post '/auth/login', JSON.generate(login: login, password: password, shrimp: token)

    if last_response.status == 403
      raise "CSRF rejected by the stack (403): #{last_response.body}. " \
            'This is a session/middleware problem, not a restrict_to result.'
    end

    last_response
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
end
