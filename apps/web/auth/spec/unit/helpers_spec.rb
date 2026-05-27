# apps/web/auth/spec/unit/helpers_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Application::AuthStrategies::Helpers#build_metadata
#
# Locks down the IP-resolution contract for the metadata hash that
# auth strategies emit. The key behavior under test: `metadata[:ip]`
# must flow through `Rack::Request#ip` so that the trusted-proxy
# initializer (lib/onetime/initializers/configure_trusted_proxy.rb)
# can influence it. Without trusted-proxy enabled, it falls back to
# `REMOTE_ADDR` (no regression for default deployments).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/helpers_spec.rb

require_relative '../spec_helper'

require 'rack/request'
require 'onetime/application/auth_strategies/helpers'
require 'onetime/initializers/configure_trusted_proxy'

RSpec.describe Onetime::Application::AuthStrategies::Helpers do
  # Anonymous host that mixes in the module so we can call its instance methods.
  let(:host) do
    Class.new do
      include Onetime::Application::AuthStrategies::Helpers
    end.new
  end

  # ---------------------------------------------------------------------------
  # GLOBAL STATE PROTECTION
  # ---------------------------------------------------------------------------
  # The trusted-proxy initializer mutates Rack::Request globally
  # (forwarded_priority, ip_filter, and class_eval'd #ip). Capture & restore
  # around each spec so test order can't leak state into unrelated suites.
  # Mirrors the pattern used in
  # spec/unit/onetime/initializers/configure_trusted_proxy_spec.rb.
  # ---------------------------------------------------------------------------
  before do
    @saved_forwarded_priority = Rack::Request.forwarded_priority
    @saved_ip_filter          = Rack::Request.ip_filter
    @saved_ip_method          = Rack::Request.instance_method(:ip)
  end

  after do
    Rack::Request.forwarded_priority = @saved_forwarded_priority
    Rack::Request.ip_filter          = @saved_ip_filter
    original_method = @saved_ip_method
    Rack::Request.class_eval do
      define_method(:ip, original_method)
    end
  end

  # Apply the trusted-proxy initializer with the supplied config hash.
  # Stubs OT.conf so we don't need a real config file or app boot.
  def apply_trusted_proxy_config(trusted_proxy_config)
    instance = Onetime::Initializers::ConfigureTrustedProxy.new
    logger   = double('logger', debug: nil, info: nil, warn: nil)
    allow(instance).to receive(:app_logger).and_return(logger)
    allow(OT).to receive(:conf).and_return(
      'site' => { 'network' => { 'trusted_proxy' => trusted_proxy_config } }
    )
    instance.execute({})
  end

  describe '#build_metadata' do
    # -----------------------------------------------------------------
    # 1) Default / no proxy config: REMOTE_ADDR is preserved.
    # -----------------------------------------------------------------
    context 'with no trusted-proxy configuration and no XFF header' do
      let(:env) do
        {
          'REMOTE_ADDR'     => '198.51.100.7',
          'HTTP_USER_AGENT' => 'Mozilla/5.0 (Test)',
          'onetime.domain_strategy' => :canonical,
          'onetime.display_domain'  => 'example.com',
        }
      end

      it 'sets metadata[:ip] to REMOTE_ADDR (backwards compatible)' do
        expect(host.build_metadata(env)[:ip]).to eq('198.51.100.7')
      end

      it 'populates user_agent, domain_strategy, and display_domain' do
        metadata = host.build_metadata(env)
        expect(metadata[:user_agent]).to eq('Mozilla/5.0 (Test)')
        expect(metadata[:domain_strategy]).to eq(:canonical)
        expect(metadata[:display_domain]).to eq('example.com')
      end
    end

    # -----------------------------------------------------------------
    # 2) Trusted-proxy filter mode honors XFF (the actual bug fix).
    # -----------------------------------------------------------------
    context 'when trusted_proxy is enabled in filter mode and XFF carries the client IP' do
      before do
        # RFC1918 peer with a CDN-style public proxy as the immediate hop
        # is trusted out-of-the-box via Rack's default ip_filter, but we
        # also add a custom CIDR for explicitness.
        apply_trusted_proxy_config(
          'enabled' => true,
          'mode'    => 'filter',
          'cidrs'   => ['10.0.0.0/8'],
        )
      end

      let(:env) do
        {
          'REMOTE_ADDR'          => '10.0.0.5',                # trusted (RFC1918 + custom CIDR)
          'HTTP_X_FORWARDED_FOR' => '203.0.113.45, 10.0.0.5',  # real client first
          'HTTP_USER_AGENT'      => 'curl/8.4.0',
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
    # 3) Trusted-proxy disabled: XFF must NOT be trusted (anti-spoof).
    # -----------------------------------------------------------------
    context 'when trusted_proxy is disabled and an attacker sends a spoofed XFF' do
      before do
        apply_trusted_proxy_config('enabled' => false)
      end

      let(:env) do
        {
          # Real peer is a public IP — Rack defaults would only walk XFF
          # if REMOTE_ADDR were trusted. With a public peer, Rack returns
          # REMOTE_ADDR regardless of XFF, so spoofing is blocked.
          'REMOTE_ADDR'          => '198.51.100.7',
          'HTTP_X_FORWARDED_FOR' => '1.2.3.4',  # spoofed
          'HTTP_USER_AGENT'      => 'evil/1.0',
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
    # 4) `additional` overrides built-in keys (preserves merge contract).
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
