# spec/integration/all/colonel_session_lifetime_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — admin-surface session lifetime (#4331)
# =============================================================================
#
# FINDING: one onetime.session cookie served colonel and customer alike on a 24h
# ROLLING TTL. Onetime::Session#write_session re-applies expire_after on every
# commit and Rack commits on essentially every request, so a colonel session left
# open in a tab was a standing administrative capability with no absolute cap and
# no idle timeout.
#
# CODE PATH under test, end to end through the real Rack::URLMap:
#
#   Onetime::Session (universal mount)
#     -> BaseSessionAuthStrategy#authenticate       (after the credential watermark)
#     -> AdminSessionLifetime#admin_session_expiry_reason
#     -> 401 [ADMIN_SESSION_EXPIRED] ...            (JSON, via Otto's ResponseBuilder)
#   ... and on the way out:
#   Onetime::Session#write_session -> Sessions::TrackMetadata (SKIPPED when refused)
#
# What only THIS file can prove, and what the design exists to guarantee:
#
#   1. The bound is on the SURFACE, not the session. The SAME cookie that is
#      refused by /api/colonel still works on a tenant route and still loads the
#      /colonel SPA shell — a colonel who is also the site's only customer must
#      not be logged out of the customer app.
#   2. A refused request does not slide its own idle window forward. Without the
#      TrackMetadata suppression the bound would cost an attacker exactly one
#      401 (the M-5 shape: no endpoint, the elevation status read included, may
#      act as a keep-alive for a session that is already over the bound).
#
# The decision table itself is the unit spec
# (spec/unit/onetime/application/auth_strategies/admin_session_lifetime_spec.rb);
# the wiring/order is base_session_auth_strategy_spec.rb.
#
# spec/config.test.yaml ships site.admin.session.enabled:false so a long suite
# cannot cut its own colonel session off mid-run; every example here enables the
# bounds it needs in-process and restores the config afterwards.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
#     spec/integration/all/colonel_session_lifetime_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'
require 'colonel/application'

RSpec.describe 'Admin-surface session lifetime (#4331)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Without this, Rack::URLMap has no /api/* entries and every request 404s at
    # the map level — which would look exactly like an expired session.
    Onetime::Application::Registry.prepare_application_registry
  end

  # Memoized: repeated generate_rack_url_map calls corrupt middleware state.
  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:now) { Familia.now.to_i }

  before do
    @saved_conf = YAML.load(YAML.dump(OT.conf))
  end

  after { OT.send(:conf=, @saved_conf) if @saved_conf }

  def configure_bounds(**settings)
    conf = YAML.load(YAML.dump(OT.conf))
    ((conf['site'] ||= {})['admin'] ||= {})['session'] =
      { 'enabled' => true }.merge(settings.transform_keys(&:to_s))
    OT.send(:conf=, conf)
  end

  def create_customer(role: 'customer')
    cust          = Onetime::Customer.create!(email: "#{role}-#{SecureRandom.hex(6)}@example.com")
    cust.role     = role
    cust.verified = 'true'
    cust.save
    cust
  end

  let(:colonel) { create_customer(role: 'colonel') }

  # Otto's session auth strategy reads env['rack.session']; injecting the hash is
  # the established pattern here (colonel_host_allowlist_spec.rb). Rack's
  # prepare_session MERGES it into the real SessionHash, so the session still has
  # a live sid and still commits — which is what lets this file drive the sidecar
  # and the rolling-TTL behaviour rather than mocking them.
  def signed_in_as(user, authenticated_at: now)
    env 'rack.session', {
      'external_id' => user.extid,
      'authenticated' => true,
      'authenticated_at' => authenticated_at,
      'role' => user.role,
    }
  end

  def json_get(path)
    header 'Accept', 'application/json'
    get path
    last_response
  end

  def html_get(path)
    header 'Accept', 'text/html'
    get path
    last_response
  end

  # The sid the stack actually minted for this rack-test session — the key both
  # the session blob and the SessionMetadata sidecar are stored under.
  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def backdate_sidecar(seconds_ago)
    record = Onetime::SessionMetadata.load(current_sid)
    raise "no sidecar for #{current_sid.inspect}; TrackMetadata did not run" if record.nil?

    record.last_activity_at = now - seconds_ago
    record.save
    record
  end

  describe 'the absolute bound' do
    before { configure_bounds(absolute_timeout: 43_200, idle_timeout: 0) }

    it 'lets a fresh colonel session through' do
      signed_in_as(colonel)

      expect(json_get('/api/colonel/info').status).to eq(200)
    end

    it 'refuses /api/colonel once the sign-in is older than the bound' do
      signed_in_as(colonel, authenticated_at: now - 43_201)

      response = json_get('/api/colonel/info')
      expect(response.status).to eq(401)
      # The marker the console branches on to render its expired banner. It rides
      # Otto's JSON auth-failure `message`; the `error` field is Otto's generic
      # "Authentication Required".
      expect(JSON.parse(response.body)['message'])
        .to match(/\A\[ADMIN_SESSION_EXPIRED\] Admin session absolute timeout exceeded/)
    end

    # THE regression this design exists to prevent. Expiring the session object
    # would log a colonel out of the customer app too, and on a self-hosted
    # install the colonel is often the only customer.
    it 'leaves the SAME session working on a tenant route' do
      signed_in_as(colonel, authenticated_at: now - 43_201)
      expect(json_get('/api/colonel/info').status).to eq(401)

      expect(json_get('/api/v2/status').status).to eq(200)
      expect(html_get('/').status).to eq(200)
    end

    # Rev-2 scope narrowing: a bare 401 on an HTML navigation has no defined UX,
    # and the expired banner lives INSIDE the SPA. The shell loads; its first API
    # call is what 401s.
    it 'still serves the /colonel SPA shell' do
      signed_in_as(colonel, authenticated_at: now - 43_201)

      expect(html_get('/colonel').status).to eq(200)
    end

    it 'is disabled by absolute_timeout: 0' do
      configure_bounds(absolute_timeout: 0, idle_timeout: 0)
      signed_in_as(colonel, authenticated_at: now - 200_000)

      expect(json_get('/api/colonel/info').status).to eq(200)
    end

    it 'is disabled wholesale by enabled: false (the suite-hygiene posture)' do
      configure_bounds(enabled: false)
      signed_in_as(colonel, authenticated_at: now - 200_000)

      expect(json_get('/api/colonel/info').status).to eq(200)
    end
  end

  describe 'the idle bound' do
    before { configure_bounds(idle_timeout: 3_600, absolute_timeout: 0) }

    it 'refuses a colonel whose sidecar activity is older than the bound' do
      signed_in_as(colonel)
      expect(json_get('/api/colonel/info').status).to eq(200)

      backdate_sidecar(3_601)

      response = json_get('/api/colonel/info')
      expect(response.status).to eq(401)
      expect(JSON.parse(response.body)['message'])
        .to match(/\A\[ADMIN_SESSION_EXPIRED\] Admin session idle timeout exceeded/)
    end

    # The M-5 regression, and the reason TrackMetadata honours the env flag: a
    # session that only ever calls the cheap elevation-status read must still be
    # expired by the idle bound. If a refused request stamped activity, the bound
    # would be a one-request speed bump — 401, then straight back in.
    it 'stays expired across repeated attempts, elevation status included' do
      signed_in_as(colonel)
      expect(json_get('/api/colonel/info').status).to eq(200)

      backdate_sidecar(3_601)

      expect(json_get('/api/colonel/elevation').status).to eq(401)
      expect(json_get('/api/colonel/elevation').status).to eq(401)
      expect(json_get('/api/colonel/info').status).to eq(401)
    end

    # Best-effort by contract: a session predating the sidecar, or one whose
    # 30-day TTL lapsed, has no record. Refusing it would log out live sessions
    # for a reason unrelated to their age.
    it 'SKIPS itself when the sidecar record is gone' do
      signed_in_as(colonel)
      expect(json_get('/api/colonel/info').status).to eq(200)

      Onetime::SessionMetadata.load(current_sid)&.destroy!

      expect(json_get('/api/colonel/info').status).to eq(200)
    end

    it 'leaves the SAME session working on a tenant route' do
      signed_in_as(colonel)
      expect(json_get('/api/colonel/info').status).to eq(200)

      backdate_sidecar(3_601)

      expect(json_get('/api/colonel/info').status).to eq(401)
      expect(html_get('/').status).to eq(200)
    end
  end

  describe 'a non-colonel account' do
    it 'is unaffected on every surface' do
      configure_bounds(absolute_timeout: 1, idle_timeout: 1)
      customer = create_customer
      signed_in_as(customer, authenticated_at: now - 200_000)

      expect(html_get('/').status).to eq(200)
      # Still 403/404 for lacking the role — never 401 for an expired admin
      # window, which is a bound this account is not subject to.
      expect(json_get('/api/colonel/info').status).not_to eq(401)
    end
  end
end
