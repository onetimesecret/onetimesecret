# spec/integration/all/router_fallback_response_headers_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, real middleware stack, real Valkey)
# =============================================================================
#
# Regression guard: a router fallback response must not carry another
# request's Set-Cookie.
#
# Every application configures Otto's `router.not_found` and
# `router.server_error` as static Rack triples built once in `build_router`:
#
#   headers             = { 'content-type' => 'application/json' }
#   router.not_found    = [404, headers, [...]]
#   router.server_error = [500, headers, [...]]
#
# Otto returns those triples BY REFERENCE (otto/core/router.rb, `@not_found`)
# on every request that matches no route. rack-session's `context` then wraps
# the returned headers in Rack::Response::Raw and `commit_session` calls
# `set_cookie` on it, which is an in-place `add_header` — and
# Rack::Utils.set_cookie_header! APPENDS when the value is already an Array.
# So one process-lifetime hash accumulated every session cookie ever committed
# on a 404/500 in that app, and any later 404 replayed all of them to whoever
# asked. Session ids are bearer tokens with no client binding.
#
# The fix mounts Onetime::Middleware::IsolateResponseHeaders innermost in
# Base#build_rack_app (directly around the router), so every middleware above
# it — the session layer, CsrfResponseHeader, DomainStrategy, RetryAfterHeader
# — writes into a per-request copy.
#
# Mode-agnostic on purpose: the router fallbacks and the middleware stack are
# identical in every AUTHENTICATION_MODE.
#
# RUN (mode-agnostic — runs in every mode lane):
#   tests/lanes/run simple --only spec/integration/all/router_fallback_response_headers_spec.rb
#
# Requires Valkey on port 2163 (pnpm run test:database:start).
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'

RSpec.describe 'Router fallback responses carry only their own Set-Cookie', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Without this, Rack::URLMap has no /api/* entries and every API request
    # 404s at the map level with Rack's own fresh triple — which would pass
    # vacuously without ever reaching an Otto router fallback.
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  # Set-Cookie values as a flat list. Rack::Test hands back either an Array or
  # a newline-joined String depending on the rack version in play; both are
  # the same wire content.
  def set_cookie_values
    raw = last_response.headers['set-cookie']
    Array(raw).flat_map { |value| value.to_s.split("\n") }.reject(&:empty?)
  end

  def session_cookie_values
    set_cookie_values.select { |cookie| cookie.start_with?('onetime.session=') }
  end

  # A miss as an anonymous client makes it: no cookie jar, nothing carried
  # over from a previous request or example.
  def miss(method, path)
    clear_cookies
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    send(method, path)
  end

  # One request per app whose only possible answer is the Otto router's
  # `not_found` fallback: no route matches and no `/404` literal fallback
  # route is defined. Web core is absent on purpose: it defines `GET /404`
  # (which HEAD shares) and every other method is refused by the CSRF layer
  # above the router, so its static triple is unreachable from here. The
  # isolation layer covers it all the same — it is mounted in Base.
  fallback_misses = {
    'API v1' => [:post, '/api/v1/__no_such_route__'],
    'API v2' => [:post, '/api/v2/__no_such_route__'],
    'API v3' => [:post, '/api/v3/__no_such_route__'],
  }

  fallback_misses.each do |app_name, (method, path)|
    describe "#{app_name}: #{method.to_s.upcase} #{path}" do
      it 'reaches the router fallback (404), so the assertions below are meaningful' do
        miss method, path

        expect(last_response.status).to eq(404)
      end

      it 'returns exactly one session cookie' do
        miss method, path

        expect(session_cookie_values.size).to eq(1)
      end

      it 'returns exactly one session cookie on the next miss as well' do
        miss method, path
        miss method, path

        expect(session_cookie_values.size).to eq(1)
      end

      it 'does not replay the previous miss\'s session cookie' do
        # `returns exactly one session cookie` above guarantees `first` is a
        # real cookie, so `not_to include(nil)` cannot pass vacuously here.
        miss method, path
        first = session_cookie_values.first

        miss method, path

        expect(session_cookie_values).not_to include(first)
      end

      it 'never accumulates across a burst of misses' do
        counts = Array.new(10) do
          miss method, path
          session_cookie_values.size
        end

        expect(counts).to all(eq(1))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # The shape the production report showed: a non-GET on a skip_paths probe
  # route is a router miss whose session is never committed (#3997), so it
  # must show NO cookie — before the fix it showed every cookie earlier
  # misses had committed while minting none of its own.
  # ---------------------------------------------------------------------------
  describe 'POST /api/v2/status (router miss on a skip_paths probe route)' do
    it 'is a router 404' do
      miss :post, '/api/v2/status'

      expect(last_response.status).to eq(404)
    end

    it 'returns no session cookie, even after other misses committed sessions' do
      3.times { miss :post, '/api/v2/__no_such_route__' }

      miss :post, '/api/v2/status'

      expect(session_cookie_values).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Control: the fallback's own headers still arrive. If the isolation layer
  # returned an empty or unrelated hash every assertion above would pass while
  # breaking the ADR-013 wire format.
  # ---------------------------------------------------------------------------
  describe 'control: the fallback triple\'s own headers survive isolation' do
    it 'keeps the JSON content type on an API miss' do
      miss :post, '/api/v2/__no_such_route__'

      expect(last_response.content_type).to include('application/json')
    end

    it 'keeps the ADR-013 body on an API miss' do
      miss :post, '/api/v2/__no_such_route__'

      expect(JSON.parse(last_response.body)).to eq('error' => 'Not Found', 'error_type' => 'NotFound')
    end
  end
end
