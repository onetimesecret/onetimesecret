# spec/unit/onetime/application/ip_privacy_parity_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'otto'
require 'onetime/application/auth_strategies/helpers'

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
      'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } },
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
        'REMOTE_ADDR' => '10.244.10.5',     # private ingress hop (trusted)
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

    # otto 2.13 (delano/otto#292): the filter walk reads X-Forwarded-For from
    # the RIGHT, skipping trusted hops, and stops at the first entry that is
    # not one. Entries left of it are client-supplied. otto 2.12 took the
    # LEFTMOST untrusted entry, which the client controls when the proxy
    # appends — the shape .env.reference used to require operators to defeat
    # by overwriting X-Forwarded-For at the edge.
    it 'skips a forged leftmost XFF entry when the appending proxy adds a public client' do
      # Client sends X-Forwarded-For: 9.9.9.9; the ingress appends the real
      # peer. chain = [9.9.9.9, 203.0.113.42], REMOTE_ADDR = trusted hop. The
      # walk stops at the peer because its address is untrusted (public).
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '9.9.9.9, 203.0.113.42',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'selects a forged entry when the client itself has a private address (the edge must overwrite)' do
      # LAN client 192.168.1.50 sends X-Forwarded-For: 203.0.113.99; the
      # appending proxy adds the client's own address. That address is in a
      # range that is always trusted, so the walk skips it as a hop and the
      # forged entry is the first untrusted one from the right. Documented in
      # docs/deployment/trusted-proxies.md ("Private clients need the
      # overwrite"): on such a network the edge must overwrite the header.
      env = {
        'REMOTE_ADDR' => '192.168.1.10',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.99, 192.168.1.50',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'resolves an all-private chain to the proxy nearest the app, not to no client IP' do
      # The same LAN client with no forged entry: every entry is a trusted
      # hop, so the walk runs out and otto falls back to REMOTE_ADDR (masked).
      env = {
        'REMOTE_ADDR' => '192.168.1.10',
        'HTTP_X_FORWARDED_FOR' => '192.168.1.50',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('192.168.1.0')
    end

    it 'treats an unlisted public hop as the client (every hop must be trusted)' do
      # CDN edge 198.51.100.7 appended itself after the visitor but is not in
      # site.network.trusted_proxy.cidrs: the walk stops at it. Under 2.12 the
      # leftmost entry won and the missing hop went unnoticed.
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42, 198.51.100.7',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('198.51.100.0')
    end

    it 'resolves the visitor once the public hop is listed in cidrs' do
      stub_trusted_proxy('enabled' => true, 'mode' => 'filter', 'cidrs' => ['198.51.100.0/24'])
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42, 198.51.100.7',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'reads X-Real-IP only when X-Forwarded-For is absent', :aggregate_failures do
      # 2.12 concatenated X-Real-IP onto the X-Forwarded-For chain; 2.13 reads
      # the first non-blank header of the family and ignores the rest.
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42',
        'HTTP_X_REAL_IP' => '9.9.9.9',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
      # Rewritten to the masked address, so nothing downstream reads 9.9.9.9.
      expect(captured[:env]['HTTP_X_REAL_IP']).to eq('203.0.113.0')
    end

    # A trusted proxy that writes a non-address where the client belongs
    # (`unknown`, an empty field) ends the walk with NO client IP. 2.12 fell
    # back to REMOTE_ADDR and made the private proxy the client — exempt
    # from masking, and the address otto.ip_match then tested.
    context 'when the trusted chain reaches a non-address entry' do
      let(:env) do
        {
          'REMOTE_ADDR' => '10.244.10.5',
          'HTTP_X_FORWARDED_FOR' => 'unknown',
          'HTTP_X_REAL_IP' => '203.0.113.42',
        }
      end

      before { build_mount.call(env) }

      it "leaves env['otto.client_ip'] absent and REMOTE_ADDR as received", :aggregate_failures do
        expect(captured[:env]).not_to have_key('otto.client_ip')
        expect(captured[:env]['REMOTE_ADDR']).to eq('10.244.10.5')
      end

      it 'installs a fail-closed otto.ip_match and records the pass in otto.peer_relayed', :aggregate_failures do
        expect(captured[:env]['otto.ip_match'].call(['0.0.0.0/0'])).to be(false)
        expect(captured[:env]).to have_key('otto.peer_relayed')
      end

      it 'deletes the forwarded address headers', :aggregate_failures do
        expect(captured[:env]).not_to have_key('HTTP_X_FORWARDED_FOR')
        expect(captured[:env]).not_to have_key('HTTP_X_REAL_IP')
      end

      # The app-side fallbacks (AuthStrategies::Helpers#client_ip, mirrored by
      # AdminNetworkIsolation#resolve_client_ip) recognise that pass and return
      # nil instead of re-resolving the proxy as the client.
      it 'resolves to no client IP in AuthStrategies::Helpers#client_ip' do
        helpers = Class.new { include Onetime::Application::AuthStrategies::Helpers }.new
        expect(helpers.send(:client_ip, captured[:env])).to be_nil
      end
    end
  end

  describe 'depth mode (count-based) behind a non-enumerable proxy tier' do
    before { stub_trusted_proxy('enabled' => true, 'mode' => 'depth', 'depth' => 1) }

    it "resolves the client by hop count into env['otto.client_ip'] and masks to its /24" do
      # Onetime depth 1 => otto trusted_proxy_depth 1 (direct mapping, no +1).
      # Honest single-proxy topology: the proxy appends the client to XFF.
      # chain = [203.0.113.42, 10.244.10.5] ; client = chain[-(1+1)].
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'never selects a forged leftmost XFF entry (padding-resistant)' do
      # A client sends its own X-Forwarded-For: 9.9.9.9 before the request
      # reaches the proxy; the proxy appends the real peer, yielding
      # XFF = [forged, client]. Positions are counted raw from the RIGHT
      # (chain = [9.9.9.9, 203.0.113.42, 10.244.10.5], client = chain[-2]),
      # so padding only pushes the forged entry further left — it is never
      # selected. Under the former +1 remap this exact shape selected the
      # forged 9.9.9.9 as the client.
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '9.9.9.9, 203.0.113.42',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'falls back to the peer (masked) on a short chain (stricter than OTS legacy)' do
      # Chain shorter than depth+1 (no XFF at all — a request that bypassed
      # the proxy tier): otto returns REMOTE_ADDR rather than a spoofable
      # forwarded entry. Here REMOTE_ADDR is private, masked to /24.
      env = { 'REMOTE_ADDR' => '10.244.10.5' }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('10.244.10.0')
    end
  end

  # otto#150: depth mode can now count hops from the RFC 7239 `Forwarded`
  # header (or `Both`), wired through MiddlewareStack from
  # site.network.trusted_proxy.header. Previously this degraded to
  # X-Forwarded-For with a boot warning; now it is genuinely honored.
  describe 'depth mode counting hops from the RFC 7239 Forwarded header' do
    before { stub_trusted_proxy('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Forwarded') }

    it "resolves the client from `Forwarded for=` into env['otto.client_ip'] and masks to its /24" do
      # Onetime depth 1 => otto depth 1; chain = Forwarded `for=` list + REMOTE_ADDR.
      # chain = [203.0.113.42, 10.244.10.5] ; client = chain[-(1+1)].
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_FORWARDED' => 'for=203.0.113.42',
        # An X-Forwarded-For present but NOT consulted in Forwarded mode.
        'HTTP_X_FORWARDED_FOR' => '198.51.100.7',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end
  end

  describe "depth mode with header 'Both'" do
    before { stub_trusted_proxy('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Both') }

    it 'prefers RFC 7239 Forwarded when it carries a for=' do
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_FORWARDED' => 'for=203.0.113.42',
        # Decoy: present but ignored because Forwarded carries a for=.
        'HTTP_X_FORWARDED_FOR' => '198.51.100.7',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('203.0.113.0')
    end

    it 'falls back to X-Forwarded-For when no Forwarded header is present' do
      env = {
        'REMOTE_ADDR' => '10.244.10.5',
        'HTTP_X_FORWARDED_FOR' => '198.51.100.7',
      }

      build_mount.call(env)

      expect(captured[:env]['otto.client_ip']).to eq('198.51.100.0')
    end
  end
end
