# spec/unit/onetime/middleware/http_origin_options_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'rack/protection'
require 'onetime/middleware/http_origin_options'

# Regression coverage for #4170: the HttpOrigin protection resolves the
# request host via Rack::Request#host (Host / X-Forwarded-Host), while the
# application's authoritative answer lives in env['onetime.display_domain']
# (DetectHost + DomainStrategy). Behind a proxy that rewrites Host to the
# canonical origin, every custom-domain POST used to 403 because Origin
# (custom domain) never matched Host (canonical origin).
#
# These specs run the real Rack::Protection::HttpOrigin with the shared
# allow_if, as both consumers mount it — the main app's Security stack and
# the auth app's production stack.
RSpec.describe Onetime::Middleware::HttpOriginOptions do
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
  let(:app) do
    Rack::Protection::HttpOrigin.new(downstream, **described_class.options)
  end

  def post(path, headers)
    env = Rack::MockRequest.env_for(path, method: 'POST', **headers)
    app.call(env).first
  end

  # The proxy shape from the issue: Host rewritten to the canonical origin,
  # true public host resolved by DetectHost/DomainStrategy upstream.
  let(:canonical_host) { 'app.example.com' }
  let(:custom_domain)  { 'tenant.example.net' }

  describe 'custom domain behind a Host-rewriting proxy' do
    it 'allows a POST whose Origin matches the resolved display domain' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}",
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(200)
    end

    it 'denies a POST whose Origin does not match the display domain' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://evil.example.org',
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(403)
    end

    it 'denies an http (non-TLS) Origin even for the correct display domain' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "http://#{custom_domain}",
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(403)
    end

    it 'denies an Origin with an appended port (exact match only)' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}:8443",
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(403)
    end
  end

  describe 'canonical host' do
    it 'still allows a same-origin POST (default HttpOrigin check)' do
      status = post('/signin',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "http://#{canonical_host}",
        'onetime.display_domain' => canonical_host,
      )
      expect(status).to eq(200)
    end

    it 'still denies a cross-origin POST' do
      status = post('/signin',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://evil.example.org',
        'onetime.display_domain' => canonical_host,
      )
      expect(status).to eq(403)
    end
  end

  describe 'fail-closed behavior without a display domain' do
    it 'denies a mismatched Origin when display_domain is absent' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}",
      )
      expect(status).to eq(403)
    end

    it 'denies a mismatched Origin when display_domain is empty' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}",
        'onetime.display_domain' => '',
      )
      expect(status).to eq(403)
    end

    it 'does not blanket-allow when Origin is also empty' do
      # ALLOW_IF must not return true for '' == 'https://' style accidents.
      expect(described_class::ALLOW_IF.call(
        'onetime.display_domain' => '', 'HTTP_ORIGIN' => ''
      )).to be(false)
    end
  end

  describe 'GET requests' do
    it 'are never blocked (safe method)' do
      env = Rack::MockRequest.env_for('/auth/sso/entra',
        method: 'GET',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://evil.example.org',
      )
      expect(app.call(env).first).to eq(200)
    end
  end

  describe 'consumers' do
    it 'is wired into the Security stack HttpOrigin component' do
      require 'onetime/middleware/security'
      options = Onetime::Middleware::Security.middleware_components['HttpOrigin'][:options]
      expect(options[:allow_if]).to eq(described_class::ALLOW_IF)
    end
  end
end
