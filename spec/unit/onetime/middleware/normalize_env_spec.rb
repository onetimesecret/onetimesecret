# spec/unit/onetime/middleware/normalize_env_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/normalize_env'

RSpec.describe Onetime::Middleware::NormalizeEnv do
  let(:downstream) do
    lambda { |env|
      [200, { 'content-type' => 'text/plain' }, [env]]
    }
  end

  let(:middleware) { described_class.new(downstream) }

  def passed_env
    _status, _headers, body = middleware.call(@env)
    body.first
  end

  it 'deletes a nil-valued CGI key (the IPPrivacyMiddleware case)' do
    @env = { 'REQUEST_METHOD' => 'GET', 'HTTP_REFERER' => nil }

    env = passed_env

    expect(env).not_to have_key('HTTP_REFERER')
    expect(env['REQUEST_METHOD']).to eq('GET')
  end

  it 'deletes every nil-valued CGI key the privacy middleware may clear' do
    @env = {
      'PATH_INFO' => '/receipt/abc',
      'HTTP_REFERER' => nil,
      'HTTP_USER_AGENT' => nil,
    }

    env = passed_env

    expect(env).not_to have_key('HTTP_REFERER')
    expect(env).not_to have_key('HTTP_USER_AGENT')
    expect(env['PATH_INFO']).to eq('/receipt/abc')
  end

  it 'leaves String CGI values untouched' do
    @env = {
      'HTTP_REFERER' => 'https://example.com/pricing',
      'HTTP_USER_AGENT' => 'curl/8.0',
    }

    env = passed_env

    expect(env['HTTP_REFERER']).to eq('https://example.com/pricing')
    expect(env['HTTP_USER_AGENT']).to eq('curl/8.0')
  end

  it 'preserves dotted keys even when nil (rack.* may legitimately be nil)' do
    @env = {
      'REQUEST_METHOD' => 'GET',
      'rack.session' => nil,
      'identity.resolved' => nil,
    }

    env = passed_env

    expect(env).to have_key('rack.session')
    expect(env).to have_key('identity.resolved')
    expect(env['rack.session']).to be_nil
  end

  it 'returns the downstream response unchanged' do
    @env = { 'REQUEST_METHOD' => 'GET' }

    status, headers, = middleware.call(@env)

    expect(status).to eq(200)
    expect(headers).to eq('content-type' => 'text/plain')
  end
end
