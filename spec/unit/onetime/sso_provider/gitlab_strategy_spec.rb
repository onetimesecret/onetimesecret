# spec/unit/onetime/sso_provider/gitlab_strategy_spec.rb
#
# frozen_string_literal: true

# Unit coverage for OmniAuth::Strategies::GitLab — the strategy the :gitlab
# definition registers, from the omniauth-gitlab fork the Gemfile pins by
# commit. The gem is outside this repo, so this spec pins the behavior the
# app relies on: moving the pinned commit to one that changes it fails here.
#
# The strategy is mounted in a bare Rack stack (no Rodauth, no app boot) and
# driven through a full authorization-code round trip. gitlab.com's token and
# user endpoints are WebMock stubs; everything between them is the real
# omniauth-oauth2 / oauth2 code the provider runs in production.
#
# OmniAuth.config is process-global; every example snapshots and restores the
# fields it touches.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/gitlab_strategy_spec.rb

require 'spec_helper'
require 'rack/mock'
require 'omniauth-gitlab'

RSpec.describe OmniAuth::Strategies::GitLab do
  let(:host) { 'https://ots.example.com' }
  let(:callback_url) { "#{host}/auth/gitlab/callback" }
  let(:session) { {} }
  let(:reached_app) { [] }
  let(:failures) { [] }

  let(:gitlab_user) do
    {
      'id' => 42,
      'username' => 'glab',
      'name' => 'Git Lab',
      'email' => 'glab@example.com',
      'avatar_url' => 'https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png',
    }
  end

  let(:app) do
    shared_session = session
    reached        = reached_app
    strategy       = described_class

    session_middleware = Class.new do
      define_method(:initialize) { |inner| @inner = inner }
      define_method(:call) do |env|
        env['rack.session'] = shared_session
        @inner.call(env)
      end
    end

    Rack::Builder.new do
      use session_middleware
      use strategy, client_id: 'gl-client-id', client_secret: 'gl-client-secret', scope: 'read_user'
      run ->(env) {
        reached << env['omniauth.auth']
        [200, { 'content-type' => 'text/plain' }, ['app']]
      }
    end.to_app
  end

  around do |example|
    config = OmniAuth.config
    saved  = {
      on_failure: config.on_failure,
      request_validation_phase: config.request_validation_phase,
      logger: config.logger,
      test_mode: config.test_mode,
      full_host: config.full_host,
    }

    recorded                        = failures
    config.test_mode                = false
    config.full_host                = nil
    config.request_validation_phase = nil
    config.logger                   = Logger.new(File::NULL)
    config.on_failure               = ->(env) {
      recorded << env['omniauth.error.type']
      [401, { 'content-type' => 'text/plain' }, ['refused']]
    }
    example.run
  ensure
    saved.each { |key, value| config.public_send(:"#{key}=", value) }
  end

  def start_login
    Rack::MockRequest.new(app).post("#{host}/auth/gitlab")
  end

  def authorize_params(response)
    URI.decode_www_form(URI(response.location).query).to_h
  end

  def stub_gitlab
    stub_request(:post, 'https://gitlab.com/oauth/token')
      .with(body: hash_including('code' => 'auth-code', 'redirect_uri' => callback_url))
      .to_return(
        status: 200,
        body: { access_token: 'gl-access-token', token_type: 'Bearer', expires_in: 7200 }.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )
    stub_request(:get, 'https://gitlab.com/api/v4/user')
      .with(headers: { 'Authorization' => 'Bearer gl-access-token' })
      .to_return(
        status: 200,
        body: gitlab_user.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )
  end

  it 'resolves from the :gitlab strategy symbol' do
    expect(OmniAuth::Strategies.const_get(OmniAuth::Utils.camelize('gitlab'), false)).to be(described_class)
  end

  describe 'request phase' do
    it 'redirects to gitlab.com with the read_user scope and a query-less redirect_uri' do
      response = start_login

      expect(response.status).to eq(302)
      expect(response.location).to start_with('https://gitlab.com/oauth/authorize?')
      expect(authorize_params(response)).to include(
        'client_id' => 'gl-client-id',
        'response_type' => 'code',
        'scope' => 'read_user',
        'redirect_uri' => callback_url,
      )
    end

    it 'binds the login to the session through omniauth.state' do
      response = start_login

      expect(session['omniauth.state']).to be_a(String).and(satisfy { |s| !s.empty? })
      expect(authorize_params(response)['state']).to eq(session['omniauth.state'])
    end
  end

  describe 'callback phase' do
    before { stub_gitlab }

    def complete_login(state: nil, extra_query: '')
      start_login
      state ||= session['omniauth.state']
      Rack::MockRequest.new(app).get("#{callback_url}?code=auth-code&state=#{state}#{extra_query}")
    end

    it 'builds the auth hash from GET /api/v4/user' do
      complete_login

      expect(failures).to be_empty
      auth = reached_app.last
      expect(auth['provider']).to eq('gitlab')
      expect(auth['uid']).to eq('42')
      expect(auth['info']).to include(
        'name' => 'Git Lab',
        'username' => 'glab',
        'email' => 'glab@example.com',
        'image' => gitlab_user['avatar_url'],
      )
      expect(auth['extra']['raw_info']).to include('id' => 42, 'username' => 'glab')
    end

    # OmniAuth's default callback_url carries the request query string. GitLab
    # rejects a token request whose redirect_uri differs from the one sent to
    # /oauth/authorize, so the extra parameters must not leak into it. The
    # token stub only matches the bare callback URL.
    it 'sends the bare callback URL as redirect_uri in the token exchange' do
      complete_login(extra_query: '&utm_source=mail')

      expect(failures).to be_empty
      expect(reached_app.last['uid']).to eq('42')
    end

    it 'refuses a callback whose state does not match the session' do
      complete_login(state: 'attacker-state')

      expect(failures).to eq([:csrf_detected])
      expect(reached_app).to be_empty
      expect(a_request(:post, 'https://gitlab.com/oauth/token')).not_to have_been_made
    end
  end
end
