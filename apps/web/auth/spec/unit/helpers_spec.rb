# apps/web/auth/spec/unit/helpers_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Application::AuthStrategies::Helpers#build_metadata
#
# Locks down the IP-resolution contract for the metadata hash that auth
# strategies emit. Post-#3436, client-IP / trusted-proxy resolution lives in
# Otto (the universal IPPrivacyMiddleware mount resolves the client once into
# env['otto.client_ip']). build_metadata therefore reads that canonical key,
# falling back to Otto::Utils.resolve_client_ip when the middleware has not run
# (e.g. this unit context with no full stack).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/helpers_spec.rb

require_relative '../spec_helper'

require 'rack/request'
require 'otto'
require 'onetime/application/auth_strategies/helpers'

RSpec.describe Onetime::Application::AuthStrategies::Helpers do
  # Anonymous host that mixes in the module so we can call its instance methods.
  let(:host) do
    Class.new do
      include Onetime::Application::AuthStrategies::Helpers
    end.new
  end

  # Build an Otto security config trusting the given proxies, as the universal
  # IPPrivacyMiddleware mount would (MiddlewareStack.ip_privacy_security_config).
  # Placed in env['otto.security_config'] so build_metadata's no-middleware
  # fallback (Otto::Utils.resolve_client_ip) sees the same trust list.
  def trusted_proxy_config(*proxies)
    cfg = Otto::Security::Config.new
    proxies.each { |p| cfg.add_trusted_proxy(p) }
    cfg
  end

  describe '#build_metadata' do
    # -----------------------------------------------------------------
    # 1) Canonical key present: build_metadata reads env['otto.client_ip'].
    # -----------------------------------------------------------------
    context "when the middleware has resolved env['otto.client_ip']" do
      let(:env) do
        {
          # REMOTE_ADDR is the (masked) value the middleware leaves behind; the
          # canonical key is what build_metadata must read.
          'REMOTE_ADDR'        => '203.0.113.0',
          'otto.client_ip'     => '203.0.113.45',
          'HTTP_USER_AGENT'    => 'curl/8.4.0',
          'onetime.domain_strategy' => :canonical,
          'onetime.display_domain'  => 'example.com',
        }
      end

      it 'sets metadata[:ip] to the canonical resolved client IP' do
        expect(host.build_metadata(env)[:ip]).to eq('203.0.113.45')
      end

      it 'populates user_agent, domain_strategy, and display_domain' do
        metadata = host.build_metadata(env)
        expect(metadata[:user_agent]).to eq('curl/8.4.0')
        expect(metadata[:domain_strategy]).to eq(:canonical)
        expect(metadata[:display_domain]).to eq('example.com')
      end
    end

    # -----------------------------------------------------------------
    # 2) No canonical key, no proxy config: REMOTE_ADDR is preserved.
    # -----------------------------------------------------------------
    context 'with no canonical IP and no trusted-proxy configuration' do
      let(:env) do
        {
          'REMOTE_ADDR'     => '198.51.100.7',
          'HTTP_USER_AGENT' => 'Mozilla/5.0 (Test)',
        }
      end

      it 'sets metadata[:ip] to REMOTE_ADDR (backwards compatible)' do
        expect(host.build_metadata(env)[:ip]).to eq('198.51.100.7')
      end
    end

    # -----------------------------------------------------------------
    # 3) No canonical key, trusted-proxy config present: the fallback
    #    resolver honors XFF (the trusted-proxy contract still holds).
    # -----------------------------------------------------------------
    context 'when no canonical IP but a trusted-proxy config resolves XFF' do
      let(:env) do
        {
          'REMOTE_ADDR'             => '10.0.0.5',                # trusted peer
          'HTTP_X_FORWARDED_FOR'    => '203.0.113.45, 10.0.0.5',  # real client first
          'HTTP_USER_AGENT'         => 'curl/8.4.0',
          'otto.security_config'    => trusted_proxy_config('10.0.0.0/8'),
        }
      end

      it 'returns the public client IP from X-Forwarded-For, not REMOTE_ADDR' do
        expect(host.build_metadata(env)[:ip]).to eq('203.0.113.45')
      end

      it 'does not return the RFC1918 peer address' do
        expect(host.build_metadata(env)[:ip]).not_to eq('10.0.0.5')
      end
    end

    # -----------------------------------------------------------------
    # 4) Untrusted peer cannot spoof via XFF (anti-spoof).
    # -----------------------------------------------------------------
    context 'when an untrusted public peer sends a spoofed XFF' do
      let(:env) do
        {
          # Public peer is not in the trusted list, so the forwarded chain is
          # not walked and REMOTE_ADDR wins.
          'REMOTE_ADDR'          => '198.51.100.7',
          'HTTP_X_FORWARDED_FOR' => '1.2.3.4',  # spoofed
          'HTTP_USER_AGENT'      => 'evil/1.0',
          'otto.security_config' => trusted_proxy_config('10.0.0.0/8'),
        }
      end

      it 'metadata[:ip] equals REMOTE_ADDR (spoofed XFF ignored)' do
        expect(host.build_metadata(env)[:ip]).to eq('198.51.100.7')
      end

      it 'metadata[:ip] does not echo the spoofed XFF value' do
        expect(host.build_metadata(env)[:ip]).not_to eq('1.2.3.4')
      end
    end

    # -----------------------------------------------------------------
    # 4b) Resolver error: the rescue logs before falling back (no longer
    #     silent), so an unexpected otto failure is detectable.
    # -----------------------------------------------------------------
    context 'when the fallback resolver raises unexpectedly' do
      let(:env) do
        {
          'REMOTE_ADDR'          => '198.51.100.7',
          'HTTP_USER_AGENT'      => 'curl/8.4.0',
          'otto.security_config' => trusted_proxy_config('10.0.0.0/8'),
        }
      end

      before do
        allow(Otto::Utils).to receive(:resolve_client_ip)
          .and_raise(StandardError, 'boom')
      end

      it 'logs the failure and falls back to the bare Rack IP' do
        expect(OT).to receive(:le).with(/\[client_ip\] resolve_client_ip failed/)
        expect(host.build_metadata(env)[:ip]).to eq('198.51.100.7')
      end
    end

    # -----------------------------------------------------------------
    # 5) `additional` overrides built-in keys (preserves merge contract).
    # -----------------------------------------------------------------
    context 'when additional metadata overrides built-in keys' do
      let(:env) do
        {
          'REMOTE_ADDR'     => '198.51.100.7',
          'HTTP_USER_AGENT' => 'Mozilla/5.0 (Test)',
        }
      end

      it 'lets `additional` override :ip' do
        metadata = host.build_metadata(env, ip: '10.10.10.10')
        expect(metadata[:ip]).to eq('10.10.10.10')
      end

      it 'lets `additional` override :user_agent' do
        metadata = host.build_metadata(env, user_agent: 'override/1.0')
        expect(metadata[:user_agent]).to eq('override/1.0')
      end

      it 'merges new keys not present in the built-in hash' do
        metadata = host.build_metadata(env, auth_method: 'session')
        expect(metadata[:auth_method]).to eq('session')
        # Built-in keys remain intact.
        expect(metadata[:ip]).to eq('198.51.100.7')
        expect(metadata[:user_agent]).to eq('Mozilla/5.0 (Test)')
      end
    end
  end
end
