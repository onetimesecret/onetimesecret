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

  def request(cookie_header, path: '/api/account/', host: nil)
    env = Rack::MockRequest.env_for(path)
    env['HTTP_HOST'] = host if host
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

    # rack-protection 4.2.1 decodes every other cookie's name with
    # Rack::Utils.unescape, which raises ArgumentError on an invalid escape;
    # unhandled, one stray malformed cookie would 500 every request.
    it 'ignores a cookie whose name is not valid percent-encoding' do
      status, _headers, body = request('onetime.session=abc; %=x')

      expect(status).to eq(200)
      expect(body.to_a.join).to eq('downstream ran')
    end

    it 'still refuses a duplicate beside a malformed name' do
      expect(request('%=x; onetime.session=a; onetime.session=b').first).to eq(403)
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

    # The gem's clear: an empty cookie with domain = request host, expires at
    # the epoch, one per prefix of the request path.
    it 'clears the offending cookie for the request host, per path prefix' do
      _status, headers, = request('onetime.session=a; onetime.session=b', path: '/api/account/', host: 'eu.example.com')
      lines = set_cookie_lines(headers)

      %w[/ /api /api/account].each do |path|
        expect(lines).to include(match(/\Aonetime\.session=;.*domain=eu\.example\.com;.*path=#{Regexp.escape(path)};.*expires=Thu, 01 Jan 1970 00:00:00 GMT/i))
      end
    end

    # A tossed cookie is set with a parent Domain= attribute, which the gem's
    # host-scoped clear never touches. The same clear for each parent domain
    # is what lets one 403 remove the planted cookie and the legitimate one,
    # so the next request starts a fresh session.
    it 'also clears the offending cookie for every parent domain with at least two labels' do
      _status, headers, = request('onetime.session=a; onetime.session=b', path: '/api/account/', host: 'a.b.example.com')
      lines = set_cookie_lines(headers)

      %w[a.b.example.com b.example.com example.com].each do |domain|
        %w[/ /api /api/account].each do |path|
          expect(lines).to include(match(/\Aonetime\.session=;.*domain=#{Regexp.escape(domain)};.*path=#{Regexp.escape(path)};/i))
        end
      end
      expect(lines).not_to include(match(/domain=com;/i))
    end

    it 'clears only for the host itself on a single-label or IP-literal host' do
      %w[localhost 127.0.0.1].each do |host|
        _status, headers, = request('onetime.session=a; onetime.session=b', host: host)
        lines = set_cookie_lines(headers)

        expect(lines).not_to be_empty
        expect(lines).to all(match(/domain=#{Regexp.escape(host)};/i))
      end
    end
  end

  describe '#parent_domains' do
    it 'lists every proper suffix with at least two labels, longest first' do
      expect(middleware.parent_domains('a.b.example.com')).to eq(%w[b.example.com example.com])
      expect(middleware.parent_domains('eu.example.com')).to eq(%w[example.com])
    end

    it 'is empty for two-label, single-label, IP-literal and blank hosts' do
      expect(middleware.parent_domains('example.com')).to eq([])
      expect(middleware.parent_domains('localhost')).to eq([])
      expect(middleware.parent_domains('127.0.0.1')).to eq([])
      expect(middleware.parent_domains('[::1]')).to eq([])
      expect(middleware.parent_domains(nil)).to eq([])
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
