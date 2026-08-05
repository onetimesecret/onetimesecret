# spec/integration/all/session_skip_probe_endpoints_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, real middleware stack, real Valkey)
# =============================================================================
#
# Regression guard for #3997: anonymous probe endpoints minted a persisted
# session per request.
#
# Onetime::Session is a Rack::Session::Abstract::PersistedSecure subclass, so
# any request that loads AND dirties the session commits it — a
# `session:<64-hex>` string key in Valkey with the full 24h TTL, plus a
# Set-Cookie. The decisive dirtier was not the app: CsrfResponseHeader calls
# `AuthenticityToken.token(session)` on every response, and that does
# `session[:csrf] ||= random`. Load balancers, uptime monitors and
# orchestrators poll /health and /api/v*/status constantly and keep no
# cookies, so every poll leaked a key nobody would ever use.
#
# The fix mounts Onetime::Middleware::SessionSkip immediately below
# Onetime::Session; it sets `env['rack.session.options'][:skip] = true` for an
# exact-match list of full external paths, which rack-session's
# `commit_session?` short-circuits on before any dirty check.
#
# Mode-agnostic on purpose: the probe endpoints and the middleware stack are
# identical in every AUTHENTICATION_MODE. /auth/health is the one exception
# (the auth app only mounts in full mode) and is covered by
# spec/integration/full/session_skip_auth_health_spec.rb.
#
# RUN (mode-agnostic — runs in every mode lane):
#   tests/lanes/run simple
#   tests/lanes/run full-sqlite
#
# Requires Valkey on port 2163 (pnpm run test:database:start).
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'

# Every probe path the middleware is configured with, minus /auth/health (full
# mode only — see spec/integration/full/session_skip_auth_health_spec.rb). A
# file-local rather than a constant so nothing leaks into the example group.
mode_agnostic_probe_paths = [
  '/health',
  '/health/advanced',
  '/api/v1/status',
  '/api/v2/status',
  '/api/v3/status',
].freeze

RSpec.describe 'Session skip on anonymous probe endpoints (#3997)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Without this, Rack::URLMap has no /api/* entries and every API request
    # 404s at the map level — which would still show "no session key" and
    # pass vacuously.
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:dbclient) { Familia.dbclient }

  # Only the rack session blob is a plain string. `session_metadata:*` is a
  # hash and the per-customer active-sessions index is a sorted set; both match
  # a naive `session*` glob and neither is the thing under test.
  def session_blob_keys
    dbclient.keys('session:*').select { |key| dbclient.type(key) == 'string' }
  end

  def set_cookie_header
    last_response.headers['set-cookie']
  end

  # A probe request as a load balancer makes it: no cookie jar, no CSRF token,
  # nothing carried over from a previous example.
  def probe(path)
    clear_cookies
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get path
  end

  # ---------------------------------------------------------------------------
  # Configuration resolution — assert the middleware is actually configured.
  # If skip_paths resolved to nil/[] every assertion below would be measuring
  # a middleware that decided nothing.
  # ---------------------------------------------------------------------------
  describe 'configuration' do
    it 'resolves a skip_paths list under the test-mode config' do
      expect(Onetime.session_config['skip_paths']).to include(*mode_agnostic_probe_paths)
    end

    it 'does not list the capability-token secret status routes' do
      skip_paths = Onetime.session_config['skip_paths']

      expect(skip_paths).to all(satisfy { |path| !path.include?('/secret/') })
    end
  end

  # ---------------------------------------------------------------------------
  # 1. Cookieless probe: no session key, no Set-Cookie, no CSRF token
  # ---------------------------------------------------------------------------
  mode_agnostic_probe_paths.each do |path|
    describe "GET #{path} without a cookie" do
      it 'is served (not a routing 404, so the assertions below are meaningful)' do
        probe path

        expect(last_response.status).to be < 400
      end

      it 'writes no session key to Valkey' do
        expect { probe path }.not_to change { session_blob_keys.size }
      end

      it 'returns no Set-Cookie header' do
        probe path

        expect(set_cookie_header).to be_nil
      end

      it 'returns no X-CSRF-Token header' do
        # AuthenticityToken.token is the dirtier; suppressing the header and
        # suppressing the write are the same act.
        probe path

        expect(last_response.headers['x-csrf-token']).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. The acceptance criterion from the issue: sustained polling adds nothing
  # ---------------------------------------------------------------------------
  describe 'sustained polling of /health' do
    it 'leaves the session key count unchanged after 100 requests' do
      before_count = session_blob_keys.size

      100.times { probe '/health' }

      expect(session_blob_keys.size).to eq(before_count)
    end

    it 'never emits a Set-Cookie across a poll burst' do
      cookie_headers = Array.new(25) do
        probe '/health'
        set_cookie_header
      end

      expect(cookie_headers.compact).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Control: a normal route still mints a session.
  #
  #    Without this, an over-broad matcher (or a session layer that stopped
  #    persisting entirely) would make every assertion above pass.
  # ---------------------------------------------------------------------------
  describe 'GET / (control — a normal route)' do
    it 'still writes a session key' do
      expect { probe '/' }.to change { session_blob_keys.size }.by(1)
    end

    it 'still returns a Set-Cookie header' do
      probe '/'

      expect(set_cookie_header).to include('onetime.session')
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Scope guard: /api/v*/secret/:identifier/status is a capability-token
  #    data read audited via SecretActivity, NOT a probe. A prefix or substring
  #    matcher would sweep it in and silently stop persisting real API sessions.
  # ---------------------------------------------------------------------------
  %w[/api/v2 /api/v3].each do |mount|
    describe "GET #{mount}/secret/:identifier/status (data read, not a probe)" do
      let(:path) { "#{mount}/secret/nonexistent#{SecureRandom.hex(8)}/status" }

      it 'reaches the logic layer rather than the URLMap 404 floor' do
        # 404 here is MissingSecret from the logic layer; either way the
        # request traversed the full middleware stack, which is what makes the
        # session assertions below meaningful.
        probe path

        expect(last_response.status).to be_between(200, 499)
      end

      it 'keeps normal session behavior (writes a session key)' do
        expect { probe path }.to change { session_blob_keys.size }.by(1)
      end

      it 'keeps returning a Set-Cookie header' do
        probe path

        expect(set_cookie_header).to include('onetime.session')
      end
    end

    describe "POST #{mount}/secret/status (batch data read, not a probe)" do
      it 'keeps normal session behavior' do
        clear_cookies
        header 'Content-Type', 'application/json'
        header 'Accept', 'application/json'

        expect { post "#{mount}/secret/status", JSON.generate(identifiers: []) }
          .to change { session_blob_keys.size }.by(1)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Existing-session survival.
  #
  #    A browser session hitting /health (the frontend polls it) must not have
  #    its session dropped, rewritten or its TTL renewed. `options[:skip]` is
  #    rack-session's "do nothing" lever, so the stored blob must be byte-identical
  #    and the TTL must keep counting down.
  # ---------------------------------------------------------------------------
  describe 'a request that presents an existing session cookie' do
    # Deliberately short so a renewal back to expire_after (86400) is
    # unmissable rather than a sub-second difference.
    let(:pinned_ttl) { 120 }

    def establish_session
      clear_cookies
      header 'Content-Type', nil
      header 'Accept', 'application/json'
      get '/'

      key = session_blob_keys.first
      raise 'control failed: GET / minted no session key' if key.nil?

      dbclient.expire(key, pinned_ttl)
      key
    end

    it 'leaves the session key in place' do
      key = establish_session

      get '/health'

      expect(dbclient.exists?(key)).to be true
    end

    it 'leaves the stored session value byte-identical' do
      key    = establish_session
      before = dbclient.get(key)

      get '/health'

      expect(dbclient.get(key)).to eq(before)
    end

    it 'does not renew the TTL upward' do
      key = establish_session

      get '/health'

      expect(dbclient.ttl(key)).to be <= pinned_ttl
    end

    it 'creates no additional session key' do
      establish_session

      expect { get '/health' }.not_to change { session_blob_keys.size }
    end

    it 'returns no Set-Cookie header' do
      establish_session

      get '/health'

      expect(set_cookie_header).to be_nil
    end

    it 'still renews normally on a non-probe route (control for the TTL assertion)' do
      # Proves the TTL assertion above can fail: the same session, same pinned
      # TTL, hitting a route that is NOT in skip_paths, does get rewritten.
      key = establish_session

      header 'Content-Type', nil
      header 'Accept', 'application/json'
      get '/'

      expect(dbclient.ttl(key)).to be > pinned_ttl
    end
  end
end
