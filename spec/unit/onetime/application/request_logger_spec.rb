# spec/unit/onetime/application/request_logger_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'
require 'json'

RSpec.describe Onetime::Application::RequestLogger do
  # Capture what the HTTP logger receives. log_request calls
  # @logger.send(level, json_string), so each entry is [level, parsed_payload].
  let(:captured) { [] }
  let(:logger) do
    sink = captured
    obj  = Object.new
    %i[trace debug info warn error fatal].each do |lvl|
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
    lambda do |env|
      env['otto.error_type'] = error_type if error_type
      [status, {}, []]
    end
  end
  let(:status) { 200 }
  let(:error_type) { nil }

  subject(:middleware) { described_class.new(downstream, config) }

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
      original_conf         = Onetime.logging_conf
      Onetime.logging_conf  = { 'http' => { 'allowed_error_fields' => allowed_fields } }
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
  end
end
