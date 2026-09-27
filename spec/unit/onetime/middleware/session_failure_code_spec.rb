# spec/unit/onetime/middleware/session_failure_code_spec.rb
#
# frozen_string_literal: true

# Otto renders the session 401 inside the gem from a failure string, so the
# evaluator's typed reason used to reach the client only as a bracket marker in
# `message`. The session strategy stashes the reason in env and this middleware
# adds `code` / `code_scope` to the body (#4462).

require 'spec_helper'
require 'json'
require 'onetime/middleware/session_failure_code'

RSpec.describe Onetime::Middleware::SessionFailureCode do
  let(:env_key) { described_class::ENV_KEY }

  let(:otto_body) do
    {
      error: 'Authentication Required',
      message: '[SESSION_SURFACE_MISMATCH] Session surface does not match request; sign in again',
      timestamp: 1_700_000_000,
    }.to_json
  end

  # What Otto's auth chain leaves behind when every strategy failed.
  let(:failed_chain) do
    Struct.new(:metadata).new({ auth_failure: 'All authentication strategies failed', failure_reasons: [] })
  end

  def otto_response(status: 401, body: otto_body, content_type: 'application/json')
    [status, { 'content-type' => content_type, 'content-length' => body.bytesize.to_s }, [body]]
  end

  def call(response, env)
    described_class.new(->(_env) { response }).call(env)
  end

  def refused_env(reason, extra = {})
    { env_key => reason, 'otto.strategy_result' => failed_chain }.merge(extra)
  end

  describe 'a session refusal rendered by Otto' do
    subject(:result) { call(otto_response, refused_env(:surface_mismatch)) }

    let(:parsed) { JSON.parse(result[2].join) }

    it 'adds the code and its scope' do
      expect(parsed).to include('code' => 'surface_mismatch', 'code_scope' => 'customer_session')
    end

    it 'keeps the status and every existing field' do
      expect(result[0]).to eq(401)
      expect(parsed).to include(JSON.parse(otto_body))
    end

    it 'recomputes content-length for the new body' do
      expect(result[1]['content-length']).to eq(result[2].join.bytesize.to_s)
    end

    it 'writes content-length under the key the app used' do
      response = [401, { 'Content-Type' => 'application/json', 'Content-Length' => '1' }, [otto_body]]
      _status, headers, body = call(response, refused_env(:surface_mismatch))

      expect(headers.keys).to contain_exactly('Content-Type', 'Content-Length')
      expect(headers['Content-Length']).to eq(body.join.bytesize.to_s)
    end
  end

  it 'scopes an outage as verification_unavailable' do
    _s, _h, body = call(otto_response, refused_env(:customer_unavailable))

    expect(JSON.parse(body.join)).to include(
      'code' => 'customer_unavailable', 'code_scope' => 'verification_unavailable',
    )
  end

  it 'scopes the admin timeout as admin_session' do
    _s, _h, body = call(otto_response, refused_env(:admin_session_expired))

    expect(JSON.parse(body.join)).to include(
      'code' => 'admin_session_expired', 'code_scope' => 'admin_session',
    )
  end

  describe 'responses it leaves exactly as it found them' do
    def untouched(response, env)
      expect(call(response, env)).to eq(response)
    end

    it 'a 401 with no session refusal recorded (login or handler rejection)' do
      untouched(otto_response, { 'otto.strategy_result' => failed_chain })
    end

    it 'a 401 that did not come from the Otto auth chain' do
      # A session strategy failed, the chain fell through to noauth, and a
      # handler answered 401 for its own reasons.
      untouched(otto_response, { env_key => :not_authenticated })
      passed = Struct.new(:metadata).new({ ip: '127.0.0.0' })
      untouched(otto_response, { env_key => :not_authenticated, 'otto.strategy_result' => passed })
    end

    it 'a 401 on a request that presented an Authorization header (credential scope, #4469)' do
      untouched(otto_response, refused_env(:session_missing, 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg=='))
    end

    it 'any other status' do
      [200, 302, 403, 500, 503].each do |status|
        untouched(otto_response(status: status), refused_env(:surface_mismatch))
      end
    end

    it 'a non-JSON 401' do
      untouched(otto_response(content_type: 'text/plain', body: 'Unauthorized'), refused_env(:surface_mismatch))
    end

    it 'a 401 whose body is not a JSON object' do
      untouched(otto_response(body: '[1,2]'), refused_env(:surface_mismatch))
      untouched(otto_response(body: '{not json'), refused_env(:surface_mismatch))
    end

    it 'a 401 that already carries a code' do
      untouched(otto_response(body: { error: 'x', code: 'handler_owned' }.to_json), refused_env(:surface_mismatch))
    end

    it 'a streaming (non-Array) body' do
      streaming = Enumerator.new { |y| y << otto_body }
      response  = [401, { 'content-type' => 'application/json' }, streaming]

      expect(call(response, refused_env(:surface_mismatch))[2]).to equal(streaming)
    end

    it 'an unknown reason in env' do
      untouched(otto_response, refused_env(:no_such_reason))
    end
  end

  it 'accepts a vendor +json content type with parameters' do
    response         = otto_response(content_type: 'application/problem+json; charset=utf-8')
    _s, _h, body     = call(response, refused_env(:stale_credentials))

    expect(JSON.parse(body.join)['code']).to eq('stale_credentials')
  end
end
