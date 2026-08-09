# spec/unit/onetime/application/middleware_stack_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Application::MiddlewareStack do
  describe '.ip_privacy_security_config' do
    subject(:config) { described_class.ip_privacy_security_config }

    def stub_conf(trusted_proxy, geo = {})
      allow(OT).to receive(:conf).and_return(
        'site' => { 'network' => { 'trusted_proxy' => trusted_proxy, 'geo' => geo } },
      )
    end

    context 'when trusted_proxy is absent' do
      before { allow(OT).to receive(:conf).and_return({}) }

      it 'still masks private/localhost IPs while trusting no proxy hop' do
        # The removed per-router enable_full_ip_privacy! calls ran
        # unconditionally, so direct-connect deployments must keep masking
        # private addresses rather than leaking them unmasked.
        aggregate_failures do
          expect(config).to be_a(Otto::Security::Config)
          expect(config.ip_privacy_config.mask_private_ips).to be(true)
          expect(config.trusted_proxy?('10.0.0.1')).to be(false)
          expect(config.trusted_proxy_depth_mode?).to be(false)
        end
      end
    end

    context 'when trusted_proxy is disabled' do
      before { stub_conf('enabled' => false) }

      it 'still masks private/localhost IPs while trusting no proxy hop' do
        aggregate_failures do
          expect(config).to be_a(Otto::Security::Config)
          expect(config.ip_privacy_config.mask_private_ips).to be(true)
          expect(config.trusted_proxy?('10.0.0.1')).to be(false)
        end
      end
    end

    context 'when trusted_proxy is enabled' do
      before { stub_conf('enabled' => true) }

      it 'returns an Otto security config' do
        expect(config).to be_a(Otto::Security::Config)
      end

      it 'trusts RFC1918 proxy hops' do
        aggregate_failures do
          expect(config.trusted_proxy?('10.244.10.0')).to be(true)
          expect(config.trusted_proxy?('192.168.1.1')).to be(true)
          expect(config.trusted_proxy?('172.16.0.1')).to be(true)
          expect(config.trusted_proxy?('172.31.255.255')).to be(true)
          expect(config.trusted_proxy?('127.0.0.1')).to be(true)
          # IPv4 link-local (169.254/16)
          expect(config.trusted_proxy?('169.254.1.1')).to be(true)
        end
      end

      it 'trusts IPv6 loopback, ULA, and link-local proxy hops' do
        aggregate_failures do
          expect(config.trusted_proxy?('::1')).to be(true)            # loopback
          expect(config.trusted_proxy?('fc00::1')).to be(true)        # ULA
          expect(config.trusted_proxy?('fd12:3456::1')).to be(true)   # ULA
          expect(config.trusted_proxy?('fe80::1')).to be(true)        # link-local
          expect(config.trusted_proxy?('feb0::1')).to be(true)        # link-local /10 upper bound
        end
      end

      it 'does not trust public client addresses' do
        aggregate_failures do
          expect(config.trusted_proxy?('203.0.113.42')).to be(false)
          expect(config.trusted_proxy?('198.51.100.7')).to be(false)
          # 172.32 is outside the RFC1918 172.16/12 block
          expect(config.trusted_proxy?('172.32.0.1')).to be(false)
          # Global-unicast IPv6 (2000::/3) must not match the fc/fd/fe branches
          expect(config.trusted_proxy?('2001:db8::1')).to be(false)
          # fec0::/10 (deprecated site-local) is outside fe80::/10 link-local
          expect(config.trusted_proxy?('fec0::1')).to be(false)
        end
      end

      it 'enables full IP masking (private/localhost masked too)' do
        # One universal mount replaces the per-router enable_full_ip_privacy!
        # calls; the config must carry mask_private_ips so private addresses are
        # masked, not exempted.
        expect(config.ip_privacy_config.mask_private_ips).to be(true)
      end

      it 'uses CIDR-walk by default (no depth mode)' do
        expect(config.trusted_proxy_depth_mode?).to be(false)
      end
    end

    context 'when filter mode declares additional public CIDRs' do
      before do
        stub_conf(
          'enabled' => true,
          'mode' => 'filter',
          'cidrs' => ['203.0.113.0/24', '2001:db8::/32'],
        )
      end

      it 'trusts the configured public CIDRs in addition to RFC1918' do
        aggregate_failures do
          # configured public IPv4 CIDR
          expect(config.trusted_proxy?('203.0.113.42')).to be(true)
          # still trusts RFC1918
          expect(config.trusted_proxy?('10.244.10.0')).to be(true)
          # configured public IPv6 CIDR
          expect(config.trusted_proxy?('2001:db8::1')).to be(true)
          # an address outside both stays untrusted
          expect(config.trusted_proxy?('198.51.100.7')).to be(false)
        end
      end

      it 'ignores blank CIDR entries without raising' do
        stub_conf(
          'enabled' => true,
          'mode' => 'filter',
          'cidrs' => ['', '  ', '203.0.113.0/24'],
        )
        expect { config }.not_to raise_error
        expect(config.trusted_proxy?('203.0.113.42')).to be(true)
      end
    end

    context 'when depth mode is configured' do
      before do
        stub_conf(
          'enabled' => true,
          'mode' => 'depth',
          'depth' => 2,
        )
      end

      it 'maps Onetime depth N DIRECTLY to otto trusted_proxy_depth N' do
        # No +1: otto's chain[-(N+1)] index already accounts for the appended
        # REMOTE_ADDR, so depth N = "N proxy hops counting the connecting peer"
        # — the operator-facing meaning of `depth: N`. The former +1 remap
        # made honest documented-topology requests resolve the proxy address
        # (short-chain fallback) and let one forged leftmost XFF entry win.
        expect(config.trusted_proxy_depth).to eq(2)
      end

      it 'activates count-based depth mode' do
        expect(config.trusted_proxy_depth_mode?).to be(true)
      end

      it 'does not also register CIDR proxies (mutually exclusive in otto)' do
        expect(config.trusted_proxies).to be_empty
      end

      it 'clamps Onetime depth to 1..10' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 50)
        expect(config.trusted_proxy_depth).to eq(10) # clamp(1,10) => 10
      end

      it 'treats a zero depth as the minimum (1)' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 0)
        expect(config.trusted_proxy_depth).to eq(1) # clamp(1,10) => 1
      end

      it 'treats an absent depth as the minimum (1)' do
        stub_conf('enabled' => true, 'mode' => 'depth')
        expect(config.trusted_proxy_depth).to eq(1) # nil.to_i => 0, clamp => 1
      end
    end

    context 'when geo.header meets depth mode (#4068)' do
      # otto 2.8 raises on trusted_proxy_depth + geo_header, so the translator
      # skips the setting under depth. Skipping silently left the operator with
      # a configured-looking header, no boot signal, and '**' on every request.
      before do
        allow(OT).to receive(:lw)
        described_class.reset_warn_once!
      end

      after { described_class.reset_warn_once! }

      it 'does not pass geo_header to otto (would be a boot failure)' do
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'header' => 'X-Country')
        aggregate_failures do
          expect { config }.not_to raise_error
          expect(config.ip_privacy_config.geo_header).to be_nil
        end
      end

      it 'warns that the configured header is ignored, naming it and the alternative' do
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'header' => 'X-Country')
        config
        expect(OT).to have_received(:lw).with(/X-Country.*IGNORED.*db_path/m)
      end

      it 'warns that country resolves to ** when depth mode has no geo source at all' do
        # No operator header AND no local DB: the built-in vendor headers are
        # equally inert under depth, so geo is on but resolves nothing.
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1)
        config
        expect(OT).to have_received(:lw).with(/depth.*db_path/m)
      end

      it 'stays quiet in depth mode when a local geo DB is configured' do
        # Stub the otto-side load so this asserts the warning logic, not
        # MaxMind file handling — the earlier version swallowed every
        # exception, which would have passed even if the DB path were never
        # honored at all.
        # any_instance: the Otto::Privacy::Config is built inside
        # Otto::Security::Config.new, so there is no seam to inject a double.
        allow_any_instance_of(Otto::Privacy::Config).to receive(:load_geo_database!) # rubocop:disable RSpec/AnyInstance
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'db_path' => '/geo.mmdb')
        aggregate_failures do
          expect(config.ip_privacy_config.geo_db_path).to eq('/geo.mmdb')
          expect(OT).not_to have_received(:lw)
        end
      end

      it 'warns once per process, not once per Application subclass' do
        # Seven Application subclasses each build a stack through this method;
        # the operator should read the finding once.
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'header' => 'X-Country')
        3.times { described_class.ip_privacy_security_config }
        expect(OT).to have_received(:lw).once
      end

      it 'passes geo_header through in filter mode without warning' do
        stub_conf({ 'enabled' => true, 'mode' => 'filter' }, 'header' => 'X-Country')
        aggregate_failures do
          # otto normalizes the setting to its rack env key on assignment.
          expect(config.ip_privacy_config.geo_header).to eq('HTTP_X_COUNTRY')
          expect(OT).not_to have_received(:lw)
        end
      end
    end

    context 'when a forwarded header is configured (otto#150)' do
      it 'wires RFC 7239 Forwarded through to otto in depth mode' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Forwarded')
        expect(config.trusted_proxy_header).to eq('Forwarded')
      end

      it 'wires Both through to otto in depth mode' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Both')
        expect(config.trusted_proxy_header).to eq('Both')
      end

      it 'canonicalizes a case-insensitive header value' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'forwarded')
        expect(config.trusted_proxy_header).to eq('Forwarded')
      end

      it 'defaults to X-Forwarded-For when the header is absent' do
        stub_conf('enabled' => true, 'mode' => 'filter')
        expect(config.trusted_proxy_header).to eq('X-Forwarded-For')
      end

      it 'treats a blank header as the default (no raise)' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => '  ')
        expect { config }.not_to raise_error
        expect(config.trusted_proxy_header).to eq('X-Forwarded-For')
      end

      it 'fails the boot loudly on an unrecognized header (no silent mis-resolution)' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Banana')
        expect { config }.to raise_error(ArgumentError, /trusted_proxy_header/)
      end
    end

    describe '.trusted_proxy_enabled?' do
      def stub_conf(trusted_proxy)
        allow(OT).to receive(:conf).and_return(
          'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } },
        )
      end

      it 'is false when the trusted_proxy section is absent' do
        allow(OT).to receive(:conf).and_return({})
        expect(described_class.trusted_proxy_enabled?).to be(false)
      end

      it 'is false when explicitly disabled' do
        stub_conf('enabled' => false)
        expect(described_class.trusted_proxy_enabled?).to be(false)
      end

      it 'is true only when explicitly enabled' do
        stub_conf('enabled' => true)
        expect(described_class.trusted_proxy_enabled?).to be(true)
      end
    end
  end
end
