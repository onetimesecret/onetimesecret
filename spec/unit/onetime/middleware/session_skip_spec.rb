# spec/unit/onetime/middleware/session_skip_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/session_skip'

# Unit tests for the probe-endpoint session suppression middleware (#3997).
#
# The middleware's entire job is a decision: for this request, should
# rack-session's `commit_session?` short-circuit? It expresses that by setting
# `env['rack.session.options'][:skip] = true`.
#
# Two properties carry all the risk:
#
#   1. The path it matches on is the FULL external path — SCRIPT_NAME +
#      PATH_INFO — because the universal stack runs inside Rack::URLMap and
#      PATH_INFO is therefore mount-relative. A matcher that read PATH_INFO
#      alone would skip `/api/v2/status` and `/api/v3/status` correctly by
#      accident while also skipping any other app's `/status`.
#   2. The comparison is exact equality. Prefix/substring matching would sweep
#      in `/api/v*/secret/:identifier/status`, a capability-token data read
#      audited via SecretActivity, and silently stop persisting its session.
#
# Both are asserted below as a matcher table, with the near-miss rows
# (trailing slash, case, traversal, hyphen/word extensions) present precisely
# because they are what a looser matcher would let through.
RSpec.describe Onetime::Middleware::SessionSkip do
  # The full default probe list, as shipped in SESSION_DEFAULTS and
  # config.defaults.yaml.
  let(:skip_paths) do
    %w[
      /health
      /health/advanced
      /auth/health
      /api/v1/status
      /api/v2/status
      /api/v3/status
    ]
  end

  let(:downstream_calls) { [] }

  # Records the env exactly as the app below the middleware sees it, which is
  # the only place the :skip flag is observable before rack-session reads it
  # back out on the way up.
  let(:downstream) do
    lambda do |env|
      downstream_calls << env
      [200, { 'content-type' => 'text/plain' }, ['ok']]
    end
  end

  let(:middleware) { described_class.new(downstream, skip_paths: skip_paths) }

  # Mirrors what rack-session's `prepare_session` installs before calling
  # downstream: a session hash plus the per-request options hash whose :skip
  # key `commit_session?` consults.
  def env_for(script_name, path_info, session_options: {})
    {
      'SCRIPT_NAME' => script_name,
      'PATH_INFO' => path_info,
      'REQUEST_METHOD' => 'GET',
      'rack.session.options' => session_options,
    }
  end

  def skip_flag_for(script_name, path_info)
    env = env_for(script_name, path_info)
    middleware.call(env)
    env['rack.session.options'][:skip]
  end

  describe 'paths that suppress session persistence' do
    # [SCRIPT_NAME, PATH_INFO, description of the mount it arrives from]
    [
      ['',         '/health',          'core app mounted at /'],
      ['',         '/health/advanced', 'core app, nested health path'],
      ['/auth',    '/health',          'auth app mounted at /auth (full mode only)'],
      ['/api/v1',  '/status',          'API v1 app'],
      ['/api/v2',  '/status',          'API v2 app'],
      ['/api/v3',  '/status',          'API v3 app'],
    ].each do |script_name, path_info, mount_description|
      it "sets :skip for #{script_name}#{path_info} (#{mount_description})" do
        expect(skip_flag_for(script_name, path_info)).to be true
      end
    end

    it 'still calls the downstream app' do
      env = env_for('', '/health')

      status, _headers, body = middleware.call(env)

      expect(status).to eq(200)
      expect(body).to eq(['ok'])
      expect(downstream_calls.size).to eq(1)
    end

    it 'sets :skip before the downstream app runs' do
      # Ordering matters: CsrfResponseHeader sits below this middleware and
      # reads the flag to decide whether to mint a token. If the flag were set
      # after @app.call, the token would already have dirtied the session.
      observed = nil
      app      = lambda do |env|
        observed = env['rack.session.options'][:skip]
        [200, {}, []]
      end

      described_class.new(app, skip_paths: skip_paths).call(env_for('', '/health'))

      expect(observed).to be true
    end
  end

  describe 'paths that must keep normal session behavior' do
    # Every row here is a path a looser matcher would wrongly capture.
    [
      ['/api/v2', '/secret/abc/status', 'capability-token data read, not a probe (substring match would catch it)'],
      ['/api/v3', '/secret/abc/status', 'v3 capability-token data read'],
      ['',        '/statusboard',       'prefix match would catch it'],
      ['',        '/health-check',      'prefix match would catch it'],
      ['',        '/healthz',           'prefix match would catch it'],
      ['',        '/',                  'homepage — the session-minting control'],
      ['',        '/health/../colonel', 'unnormalized traversal must not match /health'],
      ['/api/v2', '/status/',           'trailing slash is a different path'],
      ['',        '/HEALTH',            'matching is case-sensitive'],
      ['/api/v2', '/api/v2/status',     'double-prefixed path'],
      ['/auth',   '/auth/health',       'double-prefixed auth health path'],
      ['',        '/health/advanced/x', 'nested below a listed path'],
    ].each do |script_name, path_info, rationale|
      it "does not set :skip for #{script_name}#{path_info} (#{rationale})" do
        expect(skip_flag_for(script_name, path_info)).to be_nil
      end
    end

    it 'does not add any key to the session options hash' do
      env = env_for('', '/')

      middleware.call(env)

      expect(env['rack.session.options']).to be_empty
    end
  end

  describe 'session options hash handling' do
    it 'does nothing and does not raise when rack.session.options is absent' do
      # Happens if this middleware is ever mounted above the session
      # middleware, or in a stack with no session at all. There is nothing to
      # suppress, so the only correct behavior is to pass through.
      env = { 'SCRIPT_NAME' => '', 'PATH_INFO' => '/health' }

      status, = middleware.call(env)

      expect(status).to eq(200)
      expect(env).not_to have_key('rack.session.options')
    end

    it 'leaves the other entries of an existing options hash alone' do
      # The real hash carries the cookie settings rack-session will apply, plus
      # flags other code sets (authentication.rb requests :renew). Clobbering
      # any of them would change cookie behavior for every skipped request.
      options = { expire_after: 86_400, renew: true, path: '/', same_site: :lax }
      env     = env_for('', '/health', session_options: options)

      middleware.call(env)

      expect(env['rack.session.options']).to eq(
        expire_after: 86_400, renew: true, path: '/', same_site: :lax, skip: true
      )
    end

    it 'mutates the same hash object rack-session installed' do
      # rack-session reads back the hash it put in env; replacing it with a new
      # object would leave the original — the one commit_session? consults —
      # untouched.
      options = {}
      env     = env_for('', '/health', session_options: options)

      middleware.call(env)

      expect(env['rack.session.options']).to equal(options)
      expect(options[:skip]).to be true
    end

    it 'leaves an already-set :skip flag true' do
      env = env_for('', '/health', session_options: { skip: true })

      middleware.call(env)

      expect(env['rack.session.options'][:skip]).to be true
    end

    it 'does not clear a :skip flag another layer set on a non-probe path' do
      env = env_for('', '/', session_options: { skip: true })

      middleware.call(env)

      expect(env['rack.session.options'][:skip]).to be true
    end
  end

  describe 'skip_paths configuration' do
    it 'skips nothing when skip_paths is nil (config gap degrades to pre-#3997 behavior)' do
      env = env_for('', '/health')

      described_class.new(downstream, skip_paths: nil).call(env)

      expect(env['rack.session.options']).to be_empty
    end

    it 'skips nothing when skip_paths is empty' do
      env = env_for('', '/health')

      described_class.new(downstream, skip_paths: []).call(env)

      expect(env['rack.session.options']).to be_empty
    end

    it 'skips nothing when skip_paths is omitted entirely' do
      env = env_for('', '/health')

      described_class.new(downstream).call(env)

      expect(env['rack.session.options']).to be_empty
    end

    it 'still calls the downstream app when skip_paths is empty' do
      status, = described_class.new(downstream, skip_paths: []).call(env_for('', '/health'))

      expect(status).to eq(200)
      expect(downstream_calls.size).to eq(1)
    end

    it 'coerces non-string entries so a YAML surprise cannot break matching' do
      env = env_for('', '/health')

      described_class.new(downstream, skip_paths: [:'/health']).call(env)

      expect(env['rack.session.options'][:skip]).to be true
    end

    it 'accepts a single non-array value' do
      env = env_for('', '/health')

      described_class.new(downstream, skip_paths: '/health').call(env)

      expect(env['rack.session.options'][:skip]).to be true
    end
  end

  describe 'env key handling' do
    # A Rack-conforming server always populates both SCRIPT_NAME and
    # PATH_INFO; an env missing either means an upstream middleware
    # mangled the stack. These tests guard the matcher's nil-tolerance
    # for that degenerate input — they do not describe a request shape
    # that occurs in practice.
    it 'treats a missing SCRIPT_NAME as an empty mount prefix' do
      env = { 'PATH_INFO' => '/health', 'rack.session.options' => {} }

      middleware.call(env)

      expect(env['rack.session.options'][:skip]).to be true
    end

    it 'treats a missing PATH_INFO as an empty remainder' do
      env = { 'SCRIPT_NAME' => '/health', 'rack.session.options' => {} }

      middleware.call(env)

      expect(env['rack.session.options'][:skip]).to be true
    end

    it 'does not skip when both path components are absent' do
      env = { 'rack.session.options' => {} }

      middleware.call(env)

      expect(env['rack.session.options']).to be_empty
    end
  end

  describe 'request method independence' do
    # The probe endpoints are GET-only routes, but the skip decision is made
    # before routing. A POST to /health is a 404/405 from the router and still
    # must not mint a session.
    %w[GET HEAD POST PUT DELETE OPTIONS].each do |method|
      it "skips a #{method} request to /health" do
        env                   = env_for('', '/health')
        env['REQUEST_METHOD'] = method

        middleware.call(env)

        expect(env['rack.session.options'][:skip]).to be true
      end
    end
  end
end
