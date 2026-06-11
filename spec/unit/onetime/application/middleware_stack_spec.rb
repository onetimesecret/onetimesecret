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
        end
      end

      it 'does not trust public client addresses' do
        aggregate_failures do
          expect(config.trusted_proxy?('203.0.113.42')).to be(false)
          expect(config.trusted_proxy?('198.51.100.7')).to be(false)
          # 172.32 is outside the RFC1918 172.16/12 block
          expect(config.trusted_proxy?('172.32.0.1')).to be(false)
        end
      end
    end

  end
end
