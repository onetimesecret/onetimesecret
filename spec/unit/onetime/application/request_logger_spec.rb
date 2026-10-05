# spec/unit/onetime/application/request_logger_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'
require 'json'

RSpec.describe Onetime::Application::RequestLogger do
  # Capture what the HTTP logger receives. log_request calls
  # @logger.send(level, json_string), so each entry is [level, parsed_payload].
  subject(:middleware) { described_class.new(downstream, config) }

  let(:captured) { [] }
  let(:logger) do
    sink = captured
    obj  = Object.new
    [:trace, :debug, :info, :warn, :error, :fatal].each do |lvl|
      obj.define_singleton_method(lvl) { |msg| sink << [lvl, JSON.parse(msg)] }
    end
    obj
  end

  # capture: standard so request_id is in the payload (the field error_id used
  # to be impossible to correlate with). The downstream app stands in for the
  # Otto router: on the error path it stashes otto.error_type into env exactly
  # like OttoHooks#with_error_correlation does mid-request.
  let(:config) { { 'capture' => 'standard' } }
  let(:downstream) do
    ->(env) do
      env['otto.error_type'] = error_type if error_type
      [status, {}, []]
    end
  end
  let(:status) { 200 }
  let(:error_type) { nil }

  before { allow(Onetime).to receive(:get_logger).with('HTTP').and_return(logger) }

  def call(path: '/api/v3/secret/abc', request_id: 'req-xyz-1')
    env = Rack::MockRequest.env_for(path, 'HTTP_X_REQUEST_ID' => request_id)
    middleware.call(env)
    captured.last
  end

  context 'on a typed error response (e.g. 404 RecordNotFound)' do
    let(:status) { 404 }
    let(:error_type) { 'RecordNotFound' }

    it 'logs the request at :warn (4xx)' do
      level, _payload = call
      expect(level).to eq(:warn)
    end

    it 'records error_type alongside the request_id in a single line' do
      _level, payload = call(request_id: 'req-xyz-1')
      expect(payload['error_type']).to eq('RecordNotFound')
      expect(payload['request_id']).to eq('req-xyz-1')
      expect(payload['status']).to eq(404)
    end
  end

  context 'on a successful response' do
    let(:status) { 200 }

    it 'logs at :info and omits error_type' do
      level, payload = call
      expect(level).to eq(:info)
      expect(payload).not_to have_key('error_type')
      expect(payload['request_id']).to eq('req-xyz-1')
    end
  end

  # :minimal capture (the YAML default) normally omits request_id. Error lines
  # must still carry it so the id the client received is greppable here.
  context 'in :minimal capture mode' do
    let(:config) { { 'capture' => 'minimal' } }

    context 'on an error response' do
      let(:status) { 404 }
      let(:error_type) { 'RecordNotFound' }

      it 'forces request_id onto the line alongside error_type' do
        _level, payload = call(request_id: 'rid-min-1')
        expect(payload['error_type']).to eq('RecordNotFound')
        expect(payload['request_id']).to eq('rid-min-1')
      end
    end

    context 'on a successful response' do
      let(:status) { 200 }

      it 'stays lean (no request_id)' do
        _level, payload = call
        expect(payload).not_to have_key('request_id')
        expect(payload).not_to have_key('error_type')
      end
    end
  end

  # :debug capture is the only mode that requests :params/:headers at all.
  # It is gated by Onetime::ErrorHandler.allowed_error_fields -- the same
  # opt-in allowlist that governs Sentry's error-report request context --
  # rather than a hardcoded blocklist, so enabling LOG_HTTP_CAPTURE=debug
  # alone must never surface a secret/passphrase param or a Cookie/
  # Authorization header.
  context 'in :debug capture mode' do
    let(:config) { { 'capture' => 'debug' } }

    around do |example|
      original_conf        = Onetime.logging_conf
      Onetime.logging_conf = { 'http' => { 'allowed_error_fields' => allowed_fields } }
      example.run
      Onetime.logging_conf = original_conf
    end

    def call_with_params(params:, headers: {})
      env = Rack::MockRequest.env_for(
        '/api/v3/secret/conceal',
        { method: 'POST', params: params }.merge(headers),
      )
      middleware.call(env)
      captured.last
    end

    context 'with an empty allowlist (the default)' do
      let(:allowed_fields) { [] }

      it 'omits param values entirely, even though :debug mode requests them' do
        _level, payload = call_with_params(params: { 'secret' => 'hunter2', 'ttl' => '300' })
        expect(payload['params']).to eq({})
      end

      it 'omits header values entirely -- Cookie/Authorization never appear' do
        _level, payload = call_with_params(
          params: {},
          headers: { 'HTTP_COOKIE' => 'session=abc', 'HTTP_AUTHORIZATION' => 'Bearer xyz' },
        )
        expect(payload['headers']).to eq({})
      end
    end

    context 'with a loaded session' do
      let(:allowed_fields) { [] }
      let(:sid) { 'c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655' }

      it 'logs the session handle, never the session id (the bearer cookie value)' do
        session         = Struct.new(:id).new(Rack::Session::SessionId.new(sid))
        _level, payload = call_with_params(params: {}, headers: { 'rack.session' => session })

        expect(payload['session_handle']).to eq(Onetime::SessionMetadata.handle_for(sid))
        expect(payload).not_to have_key('session_id')
        expect(payload.to_s).not_to include(sid)
      end
    end

    context 'with an explicit allowlist' do
      let(:allowed_fields) { %w[ttl User-Agent] }

      it 'includes only the allow-listed param, never secret/passphrase' do
        _level, payload = call_with_params(
          params: { 'secret' => 'hunter2', 'passphrase' => 'p4ss', 'ttl' => '300' },
        )
        expect(payload['params']).to eq({ 'ttl' => '300' })
      end

      it 'includes only the allow-listed header' do
        _level, payload = call_with_params(
          params: {},
          headers: { 'HTTP_USER_AGENT' => 'TestAgent/1.0', 'HTTP_COOKIE' => 'session=abc' },
        )
        expect(payload['headers']).to eq({ 'User-Agent' => 'TestAgent/1.0' })
      end
    end

    context 'with the raw Rack env key form in the allowlist (namespace mismatch)' do
      # allowed_error_fields matches header names in their human-readable,
      # display form ("User-Agent"), not the raw Rack env key form
      # ("HTTP_USER_AGENT") that SENSITIVE_HEADER_KEYS elsewhere uses. Pin
      # this so a future refactor can't silently switch allowlisted_headers
      # to match on the raw env key and accidentally widen what's allowed.
      let(:allowed_fields) { ['HTTP_USER_AGENT'] }

      it 'does not match -- the raw env key form allows nothing' do
        _level, payload = call_with_params(
          params: {},
          headers: { 'HTTP_USER_AGENT' => 'TestAgent/1.0' },
        )
        expect(payload['headers']).to eq({})
      end
    end
  end
  %w[minimal standard debug].each do |mode|
    context "capability paths in #{mode} capture" do
      let(:config) { { 'capture' => mode } }

      [
        ['/secret/bearer-secret-value', '/secret/[REDACTED]'],
        ['/receipt/bearer-receipt-value/burn', '/receipt/[REDACTED]/burn'],
        ['/api/v1/private/bearer-receipt-value', '/api/v1/private/[REDACTED]'],
        ['/api/v1/metadata/bearer-receipt-value/burn', '/api/v1/metadata/[REDACTED]/burn'],
        ['/api/v2/secret/bearer-secret-value/status', '/api/v2/secret/[REDACTED]/status'],
        ['/api/v3/guest/receipt/bearer-receipt-value', '/api/v3/guest/receipt/[REDACTED]'],
        ['/api/v2/guest/secret/bearer-secret-value/reveal', '/api/v2/guest/secret/[REDACTED]/reveal'],
        ['/l/bearer-secret-value', '/l/[REDACTED]'],
        ['/incoming/bearer-receipt-value', '/incoming/[REDACTED]'],
        ['/%73ecret/bearer-secret-value', '/secret/[REDACTED]'],
        ['/secret%2Fbearer-secret-value', '/secret/[REDACTED]'],
        ['/secret/bearer%2Dsecret%2Dvalue', '/secret/[REDACTED]'],
        ['/receipt/bearer-receipt-value/bearer-secret-value', '/receipt/[REDACTED]/[REDACTED]'],
      ].each do |path, redacted|
        it "redacts #{path}" do
          _level, payload = call(path: path)
          expect(payload['path']).to eq(redacted)
          expect(payload.to_s).not_to include('bearer-secret-value', 'bearer-receipt-value')
        end
      end

      it 'redacts capability paths split across SCRIPT_NAME and PATH_INFO' do
        env = Rack::MockRequest.env_for('/bearer-secret-value')
        env['SCRIPT_NAME'] = '/mounted/api/v2/secret'
        middleware.call(env)
        expect(captured.last.last['path']).to eq('/mounted/api/v2/secret/[REDACTED]')
      end

      it 'keeps the response intact and hides unclassifiable invalid UTF-8 paths' do
        env = Rack::MockRequest.env_for('/secret/%FF')
        expect(middleware.call(env).first).to eq(200)
        expect(captured.last.last['path']).to eq('[REDACTED]')
      end

      it 'redacts repeatedly encoded capability routes' do
        expect(call(path: '/%2573ecret/bearer-secret-value').last['path']).to eq('/secret/[REDACTED]')
      end

      it 'preserves static API actions and receipt listing' do
        %w[/api/v2/secret/conceal /api/v3/guest/secret/generate /api/v2/secret/status].each do |path|
          env = Rack::MockRequest.env_for(path, method: 'POST')
          middleware.call(env)
          expect(captured.last.last['path']).to eq(path)
        end
        expect(call(path: '/api/v1/receipt/recent').last['path']).to eq('/api/v1/receipt/recent')
      end

      it 'does not exempt action-like strings on SPA capability routes' do
        expect(call(path: '/secret/conceal').last['path']).to eq('/secret/[REDACTED]')
      end

      it 'preserves the static incoming API routes' do
        [%w[GET /api/incoming/config], %w[POST /api/incoming/secret], %w[POST /api/incoming/validate]].each do |method, path|
          env = Rack::MockRequest.env_for(path, method: method)
          middleware.call(env)
          expect(captured.last.last['path']).to eq(path)
        end
        expect(call(path: '/incoming').last['path']).to eq('/incoming')
      end

      it 'does not exempt incoming API action names on the SPA route' do
        expect(call(path: '/incoming/secret').last['path']).to eq('/incoming/[REDACTED]')
      end
    end
  end

end
