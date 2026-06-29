# spec/unit/api/v1/csp_header_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Regression coverage for GitHub issue onetimesecret#3498, Item 2 (CSP hardening).
#
# Security property under test:
#   When CSP is enabled, the emitted Content-Security-Policy script-src must be
#   nonce-only ("script-src 'nonce-<value>';") and MUST NOT contain
#   'unsafe-inline' in BOTH the development and production policy branches.
#   style-src must STILL contain 'unsafe-inline' (intentional, required by Vite).
#   When CSP is disabled, no CSP header is emitted at all.
#
# This locks in apps/api/v1/controllers/helpers.rb#add_response_headers (L179 dev,
# L195 prod). It FAILS if production reverts script-src to include 'unsafe-inline'
# (the regex match below would fire) or drops the per-request nonce.

# V1::ControllerHelpers is not auto-loaded by spec_helper; require it directly.
# This file itself requires lib/onetime/helpers/session_helpers.
require_relative '../../../../apps/api/v1/controllers/helpers'

RSpec.describe V1::ControllerHelpers, '#add_response_headers (CSP hardening)' do
  # Minimal host object that mixes in the controller helpers and exposes a
  # writable `res` whose .headers is a REAL mutable Hash so we can inspect what
  # the method actually emits.
  let(:host_class) do
    Class.new do
      include V1::ControllerHelpers
      attr_accessor :res
    end
  end

  let(:headers) { {} }
  let(:res) { instance_double('Rack::Response', headers: headers) }
  let(:host) do
    h = host_class.new
    h.res = res
    h
  end

  let(:nonce) { 'TESTNONCE123' }
  let(:conf) { double('OT.conf') }

  before do
    allow(OT).to receive(:conf).and_return(conf)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:debug?).and_return(false)
  end

  # Convenience: stub the csp-enabled and development.enabled dig lookups.
  def stub_conf(csp_enabled:, development_enabled: false)
    allow(conf).to receive(:dig)
      .with('site', 'security', 'csp', 'enabled')
      .and_return(csp_enabled)
    allow(conf).to receive(:dig)
      .with('development', 'enabled')
      .and_return(development_enabled)
  end

  shared_examples 'a nonce-only script-src policy' do
    it "emits a CSP header containing the per-request nonce" do
      host.add_response_headers('text/html; charset=utf-8', nonce)
      csp = headers['content-security-policy']

      expect(csp).not_to be_nil
      expect(csp).to include("script-src 'nonce-#{nonce}';")
    end

    it "does NOT include 'unsafe-inline' anywhere in the script-src directive" do
      host.add_response_headers('text/html; charset=utf-8', nonce)
      csp = headers['content-security-policy']

      # The load-bearing regression assertion: if prod reverts to
      # "script-src 'nonce-...' 'unsafe-inline';" this fails.
      expect(csp).not_to match(/script-src[^;]*unsafe-inline/)
    end

    it "KEEPS 'unsafe-inline' in style-src (intentional, Vite)" do
      host.add_response_headers('text/html; charset=utf-8', nonce)
      csp = headers['content-security-policy']

      expect(csp).to include("style-src 'self' 'unsafe-inline';")
    end

    it 'preserves baseline hardening directives' do
      host.add_response_headers('text/html; charset=utf-8', nonce)
      csp = headers['content-security-policy']

      expect(csp).to include("default-src 'none';")
      expect(csp).to include("object-src 'none';")
      expect(csp).to include("frame-ancestors 'none';")
    end
  end

  context 'when CSP is enabled (development branch)' do
    before { stub_conf(csp_enabled: true, development_enabled: true) }

    include_examples 'a nonce-only script-src policy'

    it 'uses the permissive development connect-src' do
      host.add_response_headers('text/html; charset=utf-8', nonce)
      csp = headers['content-security-policy']

      expect(csp).to include("connect-src 'self' ws: wss: http: https:;")
    end
  end

  context 'when CSP is enabled (production branch)' do
    before { stub_conf(csp_enabled: true, development_enabled: false) }

    include_examples 'a nonce-only script-src policy'

    it 'uses the restrictive production connect-src' do
      host.add_response_headers('text/html; charset=utf-8', nonce)
      csp = headers['content-security-policy']

      expect(csp).to include("connect-src 'self' wss: https:;")
    end
  end

  context 'when CSP is disabled' do
    it 'sets no Content-Security-Policy header when enabled => false' do
      stub_conf(csp_enabled: false)
      host.add_response_headers('text/html; charset=utf-8', nonce)

      expect(headers['content-security-policy']).to be_nil
    end

    it 'sets no Content-Security-Policy header when enabled => nil' do
      stub_conf(csp_enabled: nil)
      host.add_response_headers('text/html; charset=utf-8', nonce)

      expect(headers['content-security-policy']).to be_nil
    end

    it 'treats a truthy-but-not-true value (e.g. "true" string) as disabled (strict ==)' do
      stub_conf(csp_enabled: 'true')
      host.add_response_headers('text/html; charset=utf-8', nonce)

      expect(headers['content-security-policy']).to be_nil
    end
  end

  context 'authoritative-override contracts' do
    it 'OVERRIDES a pre-existing weaker policy when CSP is ENABLED' do
      stub_conf(csp_enabled: true, development_enabled: false)
      # Pre-seed a weak upstream policy.
      headers['content-security-policy'] = 'default-src *;'

      host.add_response_headers('text/html; charset=utf-8', nonce)

      # The hardened nonce-based policy is authoritative when enabled: the weak
      # pre-existing directive is replaced entirely.
      csp = headers['content-security-policy']
      expect(csp).to include("script-src 'nonce-#{nonce}';")
      expect(csp).to include("default-src 'none';")
      expect(csp).not_to include('default-src *;')
    end

    it 'leaves a pre-existing content-security-policy header UNTOUCHED when CSP is DISABLED' do
      stub_conf(csp_enabled: false)
      headers['content-security-policy'] = 'default-src *;'

      host.add_response_headers('text/html; charset=utf-8', nonce)

      # Disabled path never touches a pre-existing header.
      expect(headers['content-security-policy']).to eq('default-src *;')
    end

    it 'defaults content-type when absent' do
      stub_conf(csp_enabled: false)
      host.add_response_headers('text/html; charset=utf-8', nonce)

      expect(headers['content-type']).to eq('text/html; charset=utf-8')
    end
  end
end
