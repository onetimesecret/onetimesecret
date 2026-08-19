# apps/web/core/spec/middleware/csp_form_action_sso_spec.rb
#
# frozen_string_literal: true

# Proves the SSO form-action override reaches the EMITTED Content-Security-Policy
# header. build_router applies the injected origins via
# router.security_config.merge_csp_directives('form-action' => "'self' <origins>");
# this drives the real emission path — Core::Middleware::RequestSetup's CSP
# chokepoint -> Otto::Security::CSP::Writer -> Config#generate_nonce_csp — with a
# security config carrying that same override, and asserts the origin lands in the
# form-action directive of the lowercase content-security-policy header.
#
# Mirrors request_setup_spec.rb (real Otto::Security::Config, stubbed OT.conf,
# no boot!, no datastore).
#
# Run: pnpm run test:rspec apps/web/core/spec/middleware/csp_form_action_sso_spec.rb

require 'spec_helper'

require_relative '../../middleware/request_setup'

RSpec.describe Core::Middleware::RequestSetup do
  subject(:middleware) { described_class.new(->(_env) { [200, {}, []] }) }

  let(:origin) { 'https://login.microsoftonline.com' }

  # A real Otto security config with nonce-CSP on, optionally carrying the SSO
  # form-action override the router applies at boot.
  def security_config(form_action_origins: nil)
    Otto::Security::Config.new.tap do |config|
      config.enable_csp_with_nonce!
      # Mirrors the boot wiring in apps/web/core/application.rb: the extras
      # channel is opt-in (default off) as of otto 2.9.
      config.enable_csp_request_extras!
      if form_action_origins
        config.merge_csp_directives('form-action' => "'self' #{form_action_origins}")
      end
    end
  end

  # Drive the finalize chokepoint helper with a stubbed OT.conf and return the
  # emitted (lowercase-key) Content-Security-Policy. env_extra lets a case add
  # request-scoped keys (e.g. otto.csp.extra_directives) to the env the
  # chokepoint hands to Otto's Writer.
  def emit(config, env_extra: {})
    conf = {
      'site' => { 'security' => { 'csp' => { 'enabled' => true } } },
      'development' => { 'enabled' => false },
    }
    allow(OT).to receive(:conf).and_return(conf)
    headers = { 'content-type' => 'text/html; charset=utf-8' }
    env = { 'otto.security_config' => config, 'onetime.nonce' => 'N' }.merge(env_extra)
    middleware.send(:emit_csp_header, headers, env)
    headers['content-security-policy']
  end

  describe 'SSO form-action widening' do
    it 'includes the injected SSO origin in the emitted form-action directive' do
      policy = emit(security_config(form_action_origins: origin))
      expect(policy).to include("form-action 'self' #{origin}")
    end

    it "keeps the default form-action 'self' and injects no origins when none merged" do
      policy = emit(security_config)
      expect(policy).to include("form-action 'self'")
      expect(policy).not_to include(origin)
    end
  end

  # Request-scoped tenant widening (#4173): Onetime::Middleware::TenantCspExtras
  # writes env['otto.csp.extra_directives'] on the way in; the chokepoint passes
  # env: to Writer.apply and otto (2.9 / delano/otto#243) sanitizes and folds
  # the extras additively at policy build. These cases drive the REAL otto
  # integration — no stubs between the env write and the emitted header.
  describe 'request-scoped form-action extras (tenant SSO)' do
    let(:tenant_origin) { 'https://idp.tenant.example' }

    it 'folds a tenant origin from the env extras into the emitted form-action' do
      policy = emit(
        security_config,
        env_extra: { 'otto.csp.extra_directives' => { 'form-action' => [tenant_origin] } },
      )
      expect(policy).to include("form-action 'self' #{tenant_origin}")
    end

    it 'appends the tenant origin after a boot-time SSO override (additive, not replacing)' do
      policy = emit(
        security_config(form_action_origins: origin),
        env_extra: { 'otto.csp.extra_directives' => { 'form-action' => [tenant_origin] } },
      )
      expect(policy).to include("form-action 'self' #{origin} #{tenant_origin}")
    end

    it 'emits the same policy for an empty extras hash as for no extras key at all' do
      without_key = emit(security_config)
      empty_hash  = emit(security_config, env_extra: { 'otto.csp.extra_directives' => {} })
      expect(empty_hash).to eq(without_key)
      expect(empty_hash).to include("form-action 'self'")
      expect(empty_hash).not_to include(tenant_origin)
    end

    it 'drops a hostile extras token at the otto boundary and keeps the policy intact' do
      policy = emit(
        security_config,
        env_extra: {
          'otto.csp.extra_directives' => {
            'form-action' => ["#{tenant_origin}; script-src https://evil.example", 'javascript:alert(1)'],
          },
        },
      )
      expect(policy).to include("form-action 'self'")
      expect(policy).not_to include('evil.example')
      expect(policy).not_to include('javascript:')
    end

    it 'refuses a script-src extra wholesale (otto REFUSED_DIRECTIVES)' do
      policy = emit(
        security_config,
        env_extra: { 'otto.csp.extra_directives' => { 'script-src' => [tenant_origin] } },
      )
      expect(policy).not_to include(tenant_origin)
    end
  end
end
