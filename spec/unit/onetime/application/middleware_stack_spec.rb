# spec/unit/onetime/application/middleware_stack_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Application::MiddlewareStack do
  describe '.ip_privacy_security_config' do
    subject(:config) { described_class.ip_privacy_security_config }

    def stub_conf(trusted_proxy)
      allow(OT).to receive(:conf).and_return(
        'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } }
      )
    end

    context 'when trusted_proxy is absent' do
      before { allow(OT).to receive(:conf).and_return({}) }

      it 'returns nil so the middleware stays in direct-connection mode' do
        expect(config).to be_nil
      end
    end

    context 'when trusted_proxy is disabled' do
      before { stub_conf('enabled' => false) }

      it 'returns nil' do
        expect(config).to be_nil
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
          'mode'    => 'filter',
          'cidrs'   => ['203.0.113.0/24', '2001:db8::/32'],
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
          'mode'    => 'filter',
          'cidrs'   => ['', '  ', '203.0.113.0/24'],
        )
        expect { config }.not_to raise_error
        expect(config.trusted_proxy?('203.0.113.42')).to be(true)
      end
    end

    context 'when depth mode is configured' do
      before do
        stub_conf(
          'enabled' => true,
          'mode'    => 'depth',
          'depth'   => 2,
        )
      end

      it 'maps Onetime depth N to otto trusted_proxy_depth N + 1' do
        # otto#151 remap: otto appends REMOTE_ADDR to the chain, one hop longer
        # than Onetime's XFF-only chain.
        expect(config.trusted_proxy_depth).to eq(3)
      end

      it 'activates count-based depth mode' do
        expect(config.trusted_proxy_depth_mode?).to be(true)
      end

      it 'does not also register CIDR proxies (mutually exclusive in otto)' do
        expect(config.trusted_proxies).to be_empty
      end

      it 'clamps Onetime depth to 1..10 before the +1 remap' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 50)
        expect(config.trusted_proxy_depth).to eq(11) # clamp(1,10) => 10, +1 => 11
      end

      it 'treats a zero/blank depth as the minimum (1) before remap' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 0)
        expect(config.trusted_proxy_depth).to eq(2) # clamp(1,10) => 1, +1 => 2
      end
    end

    context 'when an unsupported forwarded header is configured' do
      let(:warnings) { [] }

      before do
        boot_logger = instance_double('boot_logger')
        allow(boot_logger).to receive(:warn) { |msg, **kw| warnings << [msg, kw] }
        allow(Onetime).to receive(:boot_logger).and_return(boot_logger)
      end

      it 'warns and still builds an X-Forwarded-For config for Forwarded' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => 'Forwarded')

        expect(config).to be_a(Otto::Security::Config)
        # degrades to XFF: still trusts RFC1918 via the regex
        expect(config.trusted_proxy?('10.244.10.0')).to be(true)
        expect(warnings.size).to eq(1)
        expect(warnings.first.first).to match(/not supported by otto/i)
        expect(warnings.first.last[:requested]).to eq('Forwarded')
      end

      it 'warns for Both as well' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => 'Both')

        expect(config).to be_a(Otto::Security::Config)
        expect(warnings.size).to eq(1)
        expect(warnings.first.last[:requested]).to eq('Both')
      end

      it 'does not warn for the supported X-Forwarded-For header' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => 'X-Forwarded-For')

        config
        expect(warnings).to be_empty
      end
    end

    describe '.trusted_proxy_enabled?' do
      def stub_conf(trusted_proxy)
        allow(OT).to receive(:conf).and_return(
          'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } }
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
