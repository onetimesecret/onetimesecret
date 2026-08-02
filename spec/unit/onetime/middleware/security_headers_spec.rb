# spec/unit/onetime/middleware/security_headers_spec.rb
#
# frozen_string_literal: true
#
# Audit 2026-08-02, finding M-3: security headers must be emitted as real HTTP
# response headers, not only as <meta> tags in head-base.rue. These specs prove
# the Onetime::Middleware::Security collection emits:
#
#   1. X-Content-Type-Options: nosniff  (Rack::Protection::XSSHeader,
#      site.middleware.xss_header — default flipped to true)
#   2. Referrer-Policy: no-referrer     (Rack::Protection::ReferrerPolicy,
#      site.middleware.referrer_policy — no-referrer because secret URLs must
#      never leak via the Referer header)
#   3. Permissions-Policy               (Onetime::Middleware::PermissionsPolicy,
#      site.middleware.permissions_policy)
#
# and that the config defaults enable all three (env-gated via MIDDLEWARE_*).

require 'spec_helper'
require 'erb'
require 'onetime/middleware/security'

RSpec.describe 'Security header emission (audit 2026-08-02 M-3)' do
  let(:downstream) do
    ->(_env) { [200, { 'content-type' => 'application/json' }, ['{}']] }
  end

  def build_security(settings, app: downstream)
    conf = { 'site' => { 'middleware' => settings } }
    allow(Onetime).to receive(:conf).and_return(conf)
    Onetime::Middleware::Security.new(app)
  end

  def headers_for(app, path = '/')
    _status, headers, _body = app.call(Rack::MockRequest.env_for(path))
    headers
  end

  describe 'X-Content-Type-Options (xss_header)' do
    it 'emits nosniff on every response when enabled' do
      app = build_security({ 'xss_header' => true })
      expect(headers_for(app)['x-content-type-options']).to eq('nosniff')
    end

    it 'does not emit the header when disabled' do
      app = build_security({ 'xss_header' => false })
      expect(headers_for(app)).not_to have_key('x-content-type-options')
    end
  end

  describe 'Referrer-Policy (referrer_policy)' do
    it 'emits no-referrer — never the rack-protection default — when enabled' do
      app = build_security({ 'referrer_policy' => true })
      expect(headers_for(app)['referrer-policy']).to eq('no-referrer')
    end

    it 'does not clobber a policy a downstream layer already set' do
      custom = ->(_env) { [200, { 'referrer-policy' => 'same-origin' }, []] }
      app    = build_security({ 'referrer_policy' => true }, app: custom)
      expect(headers_for(app)['referrer-policy']).to eq('same-origin')
    end

    it 'does not emit the header when disabled' do
      app = build_security({ 'referrer_policy' => false })
      expect(headers_for(app)).not_to have_key('referrer-policy')
    end
  end

  describe 'Permissions-Policy (permissions_policy)' do
    it 'emits the same policy as the head-base.rue meta tag when enabled' do
      app = build_security({ 'permissions_policy' => true })
      expect(headers_for(app)['permissions-policy'])
        .to eq('geolocation=(), microphone=(), camera=()')
    end

    it 'does not emit the header when disabled' do
      app = build_security({ 'permissions_policy' => false })
      expect(headers_for(app)).not_to have_key('permissions-policy')
    end
  end

  describe 'all three together (shipped default posture)' do
    it 'emits nosniff, Referrer-Policy and Permissions-Policy on one response' do
      app     = build_security(
        {
          'xss_header' => true,
          'referrer_policy' => true,
          'permissions_policy' => true,
        },
      )
      headers = headers_for(app)

      expect(headers['x-content-type-options']).to eq('nosniff')
      expect(headers['referrer-policy']).to eq('no-referrer')
      expect(headers['permissions-policy']).to eq('geolocation=(), microphone=(), camera=()')
    end
  end

  describe Onetime::Middleware::PermissionsPolicy do
    it 'respects a downstream-set Permissions-Policy (||= semantics)' do
      custom = ->(_env) { [200, { 'permissions-policy' => 'camera=(self)' }, []] }
      app    = described_class.new(custom)
      expect(headers_for(app)['permissions-policy']).to eq('camera=(self)')
    end

    it 'accepts a policy override option' do
      app = described_class.new(downstream, policy: 'geolocation=()')
      expect(headers_for(app)['permissions-policy']).to eq('geolocation=()')
    end
  end

  describe 'config defaults (etc/defaults/config.defaults.yaml)' do
    DEFAULTS_PATH = File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml')
    TOGGLE_KEYS   = %w[MIDDLEWARE_XSS_HEADER MIDDLEWARE_REFERRER_POLICY MIDDLEWARE_PERMISSIONS_POLICY].freeze

    # Render the shipped defaults (explicit path = no layering) with a clean
    # slate for the MIDDLEWARE_* env vars so we assert the true
    # out-of-the-box posture.
    def middleware_defaults(env_overrides = {})
      saved = TOGGLE_KEYS.to_h { |k| [k, ENV.delete(k)] }
      env_overrides.each { |k, v| ENV[k] = v }
      Onetime::Config.load(DEFAULTS_PATH).dig('site', 'middleware')
    ensure
      TOGGLE_KEYS.each { |k| ENV.delete(k) }
      saved.each { |k, v| ENV[k] = v if v }
    end

    it 'ships xss_header enabled (X-Content-Type-Options: nosniff)' do
      expect(middleware_defaults['xss_header']).to be true
    end

    it 'ships referrer_policy enabled' do
      expect(middleware_defaults['referrer_policy']).to be true
    end

    it 'ships permissions_policy enabled' do
      expect(middleware_defaults['permissions_policy']).to be true
    end

    it 'still honors the env-var kill switches' do
      TOGGLE_KEYS.each do |key|
        config_key = key.sub('MIDDLEWARE_', '').downcase
        middleware = middleware_defaults(key => 'false')
        expect(middleware[config_key]).to be(false), "#{key}=false should disable #{config_key}"
      end
    end
  end
end
