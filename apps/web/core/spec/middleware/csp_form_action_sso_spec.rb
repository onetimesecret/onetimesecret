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
      if form_action_origins
        config.merge_csp_directives('form-action' => "'self' #{form_action_origins}")
      end
    end
  end

  # Drive the finalize chokepoint helper with a stubbed OT.conf and return the
  # emitted (lowercase-key) Content-Security-Policy.
  def emit(config)
    conf = {
      'site' => { 'security' => { 'csp' => { 'enabled' => true } } },
      'development' => { 'enabled' => false },
    }
    allow(OT).to receive(:conf).and_return(conf)
    headers = { 'content-type' => 'text/html; charset=utf-8' }
    env = { 'otto.security_config' => config, 'onetime.nonce' => 'N' }
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
end
