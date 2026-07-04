# apps/web/core/spec/middleware/request_setup_spec.rb
#
# frozen_string_literal: true

# Tests for Core::Middleware::RequestSetup CSP emission.
#
# RequestSetup#finalize_response is the single web chokepoint every Core response
# passes through. For HTML responses it emits a Content-Security-Policy by
# delegating to Otto's single apply core (Otto::Security::CSP::Writer, Otto >=
# 2.5) in :backstop mode — the Writer owns every emission invariant (nonce-CSP
# enabled, a present nonce, HTML-only, never clobbering an existing policy, and
# case-insensitive Content-Type / Content-Security-Policy lookups). The one gate
# that stays app-side is the site.security.csp.enabled toggle.
#
# These specs drive the private #emit_csp_header helper directly and pin the
# delegation contract and observable behavior against the REAL Writer (not a
# stubbed config), so the guards and the Writer's case-insensitive header reads
# are covered. (They exercise emit_csp_header, not the sibling `content-type ||=`
# default in #finalize_response, whose lowercase-only lookup is a separate,
# Core-scoped concern documented in the middleware.)
#
# Run: pnpm run test:rspec apps/web/core/spec/middleware/request_setup_spec.rb

require 'spec_helper'

require_relative '../../middleware/request_setup'

RSpec.describe Core::Middleware::RequestSetup do
  subject(:middleware) { described_class.new(->(_env) { [200, {}, []] }) }

  # A real Otto security config with nonce-CSP turned on: the middleware hands
  # this to Otto::Security::CSP::Writer, which reads its #csp_nonce_enabled?
  # gate and asks it for the policy via #generate_nonce_csp.
  let(:security_config) do
    Otto::Security::Config.new.tap { |config| config.enable_csp_with_nonce! }
  end

  let(:env) do
    { 'otto.security_config' => security_config, 'onetime.nonce' => 'N' }
  end

  # Drive the private chokepoint helper with a stubbed OT.conf and return the
  # resulting Content-Security-Policy header (nil when none was emitted). The
  # Writer writes the canonical lowercase key, so we read that back.
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

    it 'emits an Otto nonce policy for HTML responses when enabled' do
      expect(emit({ 'content-type' => 'text/html; charset=utf-8' })).to include("'nonce-N'")
    end

    it 'delegates to Otto with the request nonce and the development flag' do
      expect(security_config).to receive(:generate_nonce_csp)
        .with('N', development_mode: true).and_call_original
      emit({ 'content-type' => 'text/html' }, development: true)
    end

    it 'reads a canonically-cased Content-Type when emitting (Writer lookup is case-insensitive)' do
      # emit_csp_header delegates to the Writer, whose Content-Type lookup is
      # case-insensitive, so a canonically-cased key still yields a CSP. This
      # covers the Writer's read only — not finalize_response's lowercase-only
      # 'content-type ||=' default, which is Core-scoped (see the middleware).
      expect(emit({ 'Content-Type' => 'text/html; charset=utf-8' })).to include("'nonce-N'")
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
      cfg = Otto::Security::Config.new # nonce-CSP left disabled
      request_env = { 'otto.security_config' => cfg, 'onetime.nonce' => 'N' }
      expect(emit({ 'content-type' => 'text/html' }, request_env: request_env)).to be_nil
    end

    it 'skips when no Otto security config is present in env' do
      expect(emit({ 'content-type' => 'text/html' }, request_env: { 'onetime.nonce' => 'N' })).to be_nil
    end
  end
end
