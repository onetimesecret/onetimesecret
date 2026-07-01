# apps/web/core/spec/middleware/request_setup_spec.rb
#
# frozen_string_literal: true

# Tests for Core::Middleware::RequestSetup CSP emission.
#
# RequestSetup#finalize_response is the single web chokepoint every response
# passes through. For HTML responses it emits a Content-Security-Policy header,
# delegating the policy itself to Otto (the single policy source) via the Otto
# security config's #generate_nonce_csp, using the per-request nonce shared with
# the views. Emission is off unless site.security.csp.enabled is true.
#
# Run: pnpm run test:rspec apps/web/core/spec/middleware/request_setup_spec.rb

require 'spec_helper'

require_relative '../../middleware/request_setup'

RSpec.describe Core::Middleware::RequestSetup do
  subject(:middleware) { described_class.new(->(_env) { [200, {}, []] }) }

  let(:security_config) do
    instance_double(
      Otto::Security::Config,
      csp_nonce_enabled?: true,
      generate_nonce_csp: "default-src 'none'; script-src 'nonce-N'",
    )
  end

  let(:env) do
    { 'otto.security_config' => security_config, 'onetime.nonce' => 'N' }
  end

  # Drive the private chokepoint helper with a stubbed OT.conf and return the
  # resulting Content-Security-Policy header (nil when none was emitted).
  def emit(headers, csp_enabled: true, development: false, request_env: env)
    conf = {
      'site' => { 'security' => { 'csp' => { 'enabled' => csp_enabled } } },
      'development' => { 'enabled' => development },
    }
    allow(OT).to receive(:conf).and_return(conf)
    middleware.send(:emit_csp_header, headers, request_env)
    headers['content-security-policy']
  end

  describe '#emit_csp_header' do
    it 'is a no-op when site.security.csp.enabled is explicitly false (opt-out)' do
      expect(emit({ 'content-type' => 'text/html; charset=utf-8' }, csp_enabled: false)).to be_nil
    end

    it 'emits the Otto-generated policy for HTML responses when enabled' do
      expect(emit({ 'content-type' => 'text/html; charset=utf-8' }))
        .to eq("default-src 'none'; script-src 'nonce-N'")
    end

    it 'delegates the policy to Otto with the request nonce and the dev flag' do
      expect(security_config).to receive(:generate_nonce_csp).with('N', development_mode: true)
      emit({ 'content-type' => 'text/html' }, development: true)
    end

    it 'skips non-HTML responses (JSON, etc.)' do
      expect(emit({ 'content-type' => 'application/json; charset=utf-8' })).to be_nil
    end

    it 'skips when no content-type header is present' do
      expect(emit({})).to be_nil
    end

    it 'never clobbers a Content-Security-Policy already set downstream' do
      expect(emit({ 'content-type' => 'text/html', 'content-security-policy' => 'PRESET' }))
        .to eq('PRESET')
    end

    it 'skips when no nonce is present in env' do
      request_env = { 'otto.security_config' => security_config, 'onetime.nonce' => nil }
      expect(emit({ 'content-type' => 'text/html' }, request_env: request_env)).to be_nil
    end

    it 'skips when Otto nonce-CSP support is not enabled' do
      cfg = instance_double(Otto::Security::Config, csp_nonce_enabled?: false)
      request_env = { 'otto.security_config' => cfg, 'onetime.nonce' => 'N' }
      expect(emit({ 'content-type' => 'text/html' }, request_env: request_env)).to be_nil
    end

    it 'skips when no Otto security config is present in env' do
      expect(emit({ 'content-type' => 'text/html' }, request_env: { 'onetime.nonce' => 'N' })).to be_nil
    end
  end
end
