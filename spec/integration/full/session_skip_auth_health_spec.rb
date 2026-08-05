# spec/integration/full/session_skip_auth_health_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, full auth mode, real Valkey)
# =============================================================================
#
# Full-mode half of the #3997 coverage. The mode-agnostic probe endpoints live
# in spec/integration/all/session_skip_probe_endpoints_spec.rb; /auth/health is
# here because the Roda auth app only mounts when AUTHENTICATION_MODE=full.
#
# This path is the one that proves the matcher reassembles SCRIPT_NAME +
# PATH_INFO. The universal middleware stack runs INSIDE Rack::URLMap, so
# /auth/health arrives at Onetime::Middleware::SessionSkip as
# SCRIPT_NAME='/auth' + PATH_INFO='/health'. A matcher reading PATH_INFO alone
# would match it — but for the wrong reason, and it would then also match every
# other mounted app's /health. A matcher reading only the configured literal
# against PATH_INFO would miss it entirely.
#
# RUN:
#   tests/lanes/run full-sqlite
#
# Requires Valkey on port 2163 (pnpm run test:database:start).
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'

RSpec.describe 'Session skip on /auth/health (#3997)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    ENV['AUTHENTICATION_MODE'] = 'full'

    Onetime::Application::Registry.reset!
    Onetime.auth_config.reload!
    Onetime.boot! :test
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    ENV.delete('AUTHENTICATION_MODE')
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:dbclient) { Familia.dbclient }

  # Only the rack session blob is a plain string; session_metadata:* is a hash
  # and the per-customer active-sessions index is a sorted set.
  def session_blob_keys
    dbclient.keys('session:*').select { |key| dbclient.type(key) == 'string' }
  end

  # A probe as an orchestrator makes it: no cookie jar, nothing inherited.
  def probe(path)
    clear_cookies
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get path
  end

  describe 'configuration' do
    it 'lists /auth/health among the skip paths' do
      expect(Onetime.session_config['skip_paths']).to include('/auth/health')
    end
  end

  describe 'GET /auth/health without a cookie' do
    it 'returns 200 (the auth app is mounted; the assertions below are meaningful)' do
      probe '/auth/health'

      expect(last_response.status).to eq(200)
    end

    it 'reports the health payload' do
      probe '/auth/health'

      expect(JSON.parse(last_response.body)).to include('status' => 'ok')
    end

    it 'writes no session key to Valkey' do
      expect { probe '/auth/health' }.not_to change { session_blob_keys.size }
    end

    it 'returns no Set-Cookie header' do
      probe '/auth/health'

      expect(last_response.headers['set-cookie']).to be_nil
    end

    it 'returns no X-CSRF-Token header' do
      probe '/auth/health'

      expect(last_response.headers['x-csrf-token']).to be_nil
    end
  end

  describe 'sustained polling of /auth/health' do
    it 'leaves the session key count unchanged across a poll burst' do
      before_count = session_blob_keys.size

      25.times { probe '/auth/health' }

      expect(session_blob_keys.size).to eq(before_count)
    end
  end

  describe 'GET /auth (control — a normal auth-app route)' do
    # Proves the suppression is scoped to the configured path rather than to
    # the whole auth mount: without this, deleting the SCRIPT_NAME join (or
    # skipping the entire /auth app) would still leave every assertion above
    # green.
    it 'still writes a session key' do
      expect { probe '/auth' }.to change { session_blob_keys.size }.by(1)
    end

    it 'still returns a Set-Cookie header' do
      probe '/auth'

      expect(last_response.headers['set-cookie']).to include('onetime.session')
    end
  end
end
