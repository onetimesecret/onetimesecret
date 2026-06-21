# spec/unit/onetime/application/ip_privacy_parity_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'otto'

# Parity regression for onetimesecret#3436.
#
# Proves that the consolidated single IPPrivacyMiddleware mount — configured
# from MiddlewareStack.ip_privacy_security_config — resolves the real client
# from behind an RFC1918 ingress hop and masks it to its own /24, exactly as
# the original scripts/ip_privacy_trusted_proxy_repro.rb demonstrated, now via
# otto 2.3.0's canonical env['otto.client_ip'] instead of the deleted
# ConfigureTrustedProxy monkeypatch.
#
# Repro env: REMOTE_ADDR=10.244.10.5, X-Forwarded-For=203.0.113.42
#   => client resolves to 203.0.113.42, masked to 203.0.113.0
RSpec.describe 'IP privacy / trusted-proxy parity (#3436)' do
  # A terminal Rack app that captures the env the middleware produced.
  let(:captured) { {} }
  let(:terminal_app) do
    cap = captured
    ->(env) {
      cap[:env] = env
      [200, {}, ['ok']]
    }
  end

  def stub_trusted_proxy(trusted_proxy)
    allow(OT).to receive(:conf).and_return(
      'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } }
    )
  end

  # Build the universal mount exactly as MiddlewareStack.configure does:
  # IPPrivacyMiddleware wrapping the terminal app with the security config.
  def build_mount
    security_config = Onetime::Application::MiddlewareStack.ip_privacy_security_config
    Otto::Security::Middleware::IPPrivacyMiddleware.new(terminal_app, security_config)
  end

  describe 'filter mode (CIDR-walk) behind an RFC1918 ingress hop' do
    before { stub_trusted_proxy('enabled' => true, 'mode' => 'filter') }

    it "resolves the real public client into env['otto.client_ip'] and masks to its /24" do
      env = {
        'REMOTE_ADDR'          => '10.244.10.5',     # private ingress hop (trusted)
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42',    # real client
      }

      build_mount.call(env)
      resolved = captured[:env]['otto.client_ip']

      # Masked to the client's own /24 (octet_precision 1), NOT the ingress hop.
      expect(resolved).to eq('203.0.113.0')
      expect(captured[:env]['REMOTE_ADDR']).to eq('203.0.113.0')
    end

    it 'masks a private/localhost client too (full IP privacy)' do
      # No proxy chain: the private peer IS the client. Full masking is on, so
      # it is masked rather than exempted.
      env = { 'REMOTE_ADDR' => '10.0.0.7' }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('10.0.0.0')
    end
  end

  describe 'depth mode (count-based) behind a non-enumerable proxy tier' do
    before { stub_trusted_proxy('enabled' => true, 'mode' => 'depth', 'depth' => 1) }

    it "resolves the client by hop count into env['otto.client_ip'] and masks to its /24" do
      # Onetime depth 1 => otto trusted_proxy_depth 2 (chain = XFF + REMOTE_ADDR).
      # chain = [203.0.113.42, 10.244.10.5, 10.244.10.5] ; client = chain[-(2+1)].
      env = {
        'REMOTE_ADDR'          => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42, 10.244.10.5',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'falls back to the peer (masked) on a short chain (stricter than OTS)' do
      # Chain shorter than depth+1: otto returns REMOTE_ADDR rather than a
      # spoofable forwarded entry. Here REMOTE_ADDR is private, masked to /24.
      env = { 'REMOTE_ADDR' => '10.244.10.5' }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('10.244.10.0')
    end
  end
end
