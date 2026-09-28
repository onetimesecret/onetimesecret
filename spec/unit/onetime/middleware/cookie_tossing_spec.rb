# spec/unit/onetime/middleware/cookie_tossing_spec.rb
#
# frozen_string_literal: true

# RISK-2026-08-14-COOKIE-TOSSING / #4466: the session cookie may appear once
# on a request. The rack level (a duplicate never yields an authenticated
# 200, in either order) is pinned in
# spec/integration/full/customer_session_continuation_baseline_spec.rb and
# apps/web/auth/spec/integration/full_mfa/mfa_session_rotation_spec.rb.

require 'spec_helper'
require 'rack/mock'
require 'onetime/middleware/cookie_tossing'

RSpec.describe Onetime::Middleware::CookieTossing do
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['downstream ran']] } }
  let(:middleware) { described_class.new(downstream) }

  def request(cookie_header, path: '/api/account/')
    env = Rack::MockRequest.env_for(path)
    env['HTTP_COOKIE'] = cookie_header unless cookie_header.nil?
    env['rack.errors'] = StringIO.new
    middleware.call(env)
  end

  def set_cookie_lines(headers)
    Array(headers['set-cookie']).flat_map { |line| line.to_s.split("\n") }
  end

  describe 'the cookie name' do
    it 'defaults to the configured session cookie, the one Onetime::Session is mounted with' do
      expect(middleware.options[:session_key]).to eq(Onetime.session_config['key'])
      expect(middleware.options[:session_key]).to eq('onetime.session')
    end

    it 'honours an explicit session_key' do
      expect(described_class.new(downstream, session_key: 'other.session').options[:session_key]).to eq('other.session')
    end
  end

  describe 'one session cookie' do
    it 'passes the request through' do
      status, _headers, body = request('onetime.session=abc')

      expect(status).to eq(200)
      expect(body.to_a.join).to eq('downstream ran')
    end

    it 'passes a request without cookies through' do
      status, = request(nil)

      expect(status).to eq(200)
    end

    it 'does not care about other repeated cookie names' do
      status, = request('onetime.session=abc; locale=en; locale=fr')

      expect(status).to eq(200)
    end
  end

  describe 'a repeated session cookie' do
    it 'refuses the request without running the app' do
      ran = false
      app = described_class.new(lambda { |_env|
        ran = true
        [200, {}, []]
      })
      status, _headers, body = app.call(Rack::MockRequest.env_for('/', 'HTTP_COOKIE' => 'onetime.session=a; onetime.session=b'))

      expect(status).to eq(403)
      expect(body.to_a.join).not_to include('downstream')
      expect(ran).to be(false)
    end

    it 'refuses it whichever cookie comes first' do
      expect(request('onetime.session=a; onetime.session=b').first).to eq(403)
      expect(request('onetime.session=b; onetime.session=a').first).to eq(403)
    end

    it 'refuses a percent-encoded spelling of the name' do
      expect(request('onetime.session=a; onetime%2Esession=b').first).to eq(403)
    end

    # Host-scoped: the gem sets an empty cookie with domain = request host per
    # path prefix. A cookie planted with a parent Domain= attribute is not
    # cleared by this, and the browser keeps sending both until it expires.
    it 'clears the offending cookie for the request host on the response' do
      _status, headers, = request('onetime.session=a; onetime.session=b', path: '/api/account/')

      expect(set_cookie_lines(headers)).to include(a_string_starting_with('onetime.session=;'))
    end
  end

  # rack-protection 4.2.1 memoizes bad_cookies on the middleware instance and
  # never clears it, so with the stock class one refused request would refuse
  # every request that followed through the same instance.
  describe 'per-request state' do
    it 'refuses only the request that carries the duplicate' do
      expect(request('onetime.session=a; onetime.session=b').first).to eq(403)
      expect(request('onetime.session=a').first).to eq(200)
      expect(request(nil).first).to eq(200)
      expect(request('onetime.session=a; onetime.session=b').first).to eq(403)
      expect(request('onetime.session=c').first).to eq(200)
    end

    it 'leaves no bad-cookie list on the shared instance' do
      request('onetime.session=a; onetime.session=b')

      expect(middleware.instance_variable_get(:@bad_cookies)).to be_nil
    end
  end
end
