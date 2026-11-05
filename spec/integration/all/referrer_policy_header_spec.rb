# spec/integration/all/referrer_policy_header_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, real middleware stack, real Valkey)
# =============================================================================
#
# Every response carries one Referrer-Policy value,
# Onetime::Middleware::Registry::REFERRER_POLICY, whichever layer produced it.
#
# Two layers write the header. Otto stamps its own responses (routed HTML and
# JSON, its 404/500 fallbacks, static files) from security_config.referrer_policy,
# which Onetime::Application::Base sets on every Otto router. Below it,
# Rack::Protection::ReferrerPolicy (Onetime::Middleware::Security) fills the
# header only when it is missing. Before otto 2.12 the first layer was
# hard-coded to strict-origin-when-cross-origin and there was no seam to
# change it, so HTML pages carried Otto's value while the auth app carried the
# Registry's, and only the <meta name="referrer"> in head-base.rue governed
# the document (#4542). This spec asks real Otto responses, not the middleware
# in isolation, because that is exactly where the two values used to differ.
#
# Mode-agnostic: the router configuration and the middleware stack are the
# same in every AUTHENTICATION_MODE.
#
# RUN:
#   tests/lanes/run simple --only spec/integration/all/referrer_policy_header_spec.rb
#
# Requires Valkey on port 2163 (pnpm run test:database:start).
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'

RSpec.describe 'Referrer-Policy on Otto responses', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:policy) { Onetime::Middleware::Registry::REFERRER_POLICY }

  describe 'an HTML page rendered through Otto (web core)' do
    before do
      clear_cookies
      header 'Accept', 'text/html'
      get '/'
    end

    it 'renders (control: the assertions below are about a real page)' do
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/html')
    end

    it 'carries the Registry policy in the HTTP header, not Otto\'s built-in default' do
      expect(last_response.headers['referrer-policy']).to eq(policy)
    end

    it 'carries the same policy in the document meta tag' do
      content = last_response.body[/<meta name="referrer" content="([^"]+)">/, 1]
      expect(content).to eq(policy)
    end
  end

  describe 'a JSON response from an Otto router fallback (API v2 404)' do
    before do
      clear_cookies
      header 'Content-Type', 'application/json'
      header 'Accept', 'application/json'
      post '/api/v2/__no_such_route__'
    end

    it 'reaches the fallback (control)' do
      expect(last_response.status).to eq(404)
    end

    it 'carries the Registry policy' do
      expect(last_response.headers['referrer-policy']).to eq(policy)
    end
  end

  describe 'a routed JSON response (API v2 status)' do
    before do
      clear_cookies
      header 'Accept', 'application/json'
      get '/api/v2/status'
    end

    it 'carries the Registry policy' do
      expect(last_response.status).to eq(200)
      expect(last_response.headers['referrer-policy']).to eq(policy)
    end
  end
end
