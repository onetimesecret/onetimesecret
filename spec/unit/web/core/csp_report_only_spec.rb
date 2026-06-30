# spec/unit/web/core/csp_report_only_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Regression coverage for the Core web app CSP gap.
#
# Security property under test:
#   The Core web app (apps/web/core) must actually EMIT a hardened, nonce-based
#   Content-Security-Policy on its HTML responses. Previously
#   router.enable_csp_with_nonce! only set an Otto flag and emitted no header, so
#   the per-request nonce was inert and the user-facing HTML pages had zero CSP.
#
#   Core::Middleware::RequestSetup#finalize_response now emits the policy in
#   REPORT-ONLY mode (the maintainer's chosen opt-in rollout), gated on the
#   EXISTING site.security.csp.enabled flag, using the SAME shared policy builder
#   (Onetime::Security::Csp) as the enforcing V1 API path.
#
# This harness is modeled on scratchpad/csp_harness.rb: it drives the REAL
# Core::Middleware::RequestSetup with a stub downstream app and inspects the raw
# Rack headers hash.

require_relative '../../../../apps/web/core/middleware/request_setup'

RSpec.describe Core::Middleware::RequestSetup, '#finalize_response (CSP report-only)' do
  RO_HEADER  = 'content-security-policy-report-only'
  ENF_HEADER = 'content-security-policy'

  let(:conf) { double('OT.conf') }

  before do
    allow(OT).to receive(:conf).and_return(conf)
    allow(OT).to receive(:debug?).and_return(false)
  end

  def stub_conf(csp_enabled:, development_enabled: false)
    allow(conf).to receive(:dig)
      .with('site', 'security', 'csp', 'enabled')
      .and_return(csp_enabled)
    allow(conf).to receive(:dig)
      .with('development', 'enabled')
      .and_return(development_enabled)
  end

  # Build a downstream app that returns the given response and captures the
  # generated nonce out of env (RequestSetup sets it before calling downstream).
  def run(content_type: 'text/html; charset=utf-8', preset_headers: {}, capture: nil)
    downstream = lambda do |env|
      capture[:nonce] = env['onetime.nonce'] if capture
      headers = { 'content-type' => content_type }.merge(preset_headers)
      [200, headers, ['<html><body>ok</body></html>']]
    end
    middleware = described_class.new(downstream)
    middleware.call({})
  end

  context 'when CSP is enabled and the response is HTML (production)' do
    before { stub_conf(csp_enabled: true, development_enabled: false) }

    it 'emits a nonce-only report-only CSP whose nonce equals env nonce' do
      capture = {}
      _status, headers, _body = run(capture: capture)

      csp = headers[RO_HEADER]
      expect(csp).not_to be_nil
      expect(capture[:nonce]).not_to be_nil
      expect(csp).to include("script-src 'nonce-#{capture[:nonce]}';")
      # script-src must be nonce-only: no 'unsafe-inline' in that directive.
      expect(csp).not_to match(/script-src[^;]*unsafe-inline/)
      expect(csp).to include("default-src 'none';")
      # No ENFORCING header is emitted in the report-only rollout.
      expect(headers[ENF_HEADER]).to be_nil
    end

    it 'uses the restrictive production connect-src' do
      _status, headers, _body = run
      expect(headers[RO_HEADER]).to include("connect-src 'self' wss: https:;")
    end
  end

  context 'when CSP is enabled and development.enabled is true' do
    before { stub_conf(csp_enabled: true, development_enabled: true) }

    it 'uses the permissive development connect-src' do
      _status, headers, _body = run
      expect(headers[RO_HEADER]).to include("connect-src 'self' ws: wss: http: https:;")
    end
  end

  context 'when CSP is disabled' do
    it 'emits NO CSP header of either kind (enabled => false)' do
      stub_conf(csp_enabled: false)
      _status, headers, _body = run

      expect(headers[RO_HEADER]).to be_nil
      expect(headers[ENF_HEADER]).to be_nil
    end

    it 'treats a truthy-but-not-true value as disabled (strict ==)' do
      stub_conf(csp_enabled: 'true')
      _status, headers, _body = run

      expect(headers[RO_HEADER]).to be_nil
      expect(headers[ENF_HEADER]).to be_nil
    end
  end

  context 'when the response is not HTML' do
    before { stub_conf(csp_enabled: true) }

    it 'emits NO CSP header for application/json' do
      _status, headers, _body = run(content_type: 'application/json')

      expect(headers[RO_HEADER]).to be_nil
      expect(headers[ENF_HEADER]).to be_nil
    end
  end

  context 'when a CSP header already exists (defensive: do not overwrite)' do
    before { stub_conf(csp_enabled: true, development_enabled: false) }

    it 'leaves a pre-existing report-only header untouched' do
      _status, headers, _body = run(preset_headers: { RO_HEADER => 'default-src *;' })
      expect(headers[RO_HEADER]).to eq('default-src *;')
    end

    it 'does not add a report-only header when an enforcing header exists' do
      _status, headers, _body = run(preset_headers: { ENF_HEADER => 'default-src *;' })
      expect(headers[RO_HEADER]).to be_nil
      expect(headers[ENF_HEADER]).to eq('default-src *;')
    end
  end
end
