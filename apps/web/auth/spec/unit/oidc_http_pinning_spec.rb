# apps/web/auth/spec/unit/oidc_http_pinning_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::OidcHttpPinning — the process-global
# OpenIDConnect.http_config hook that pins runtime OIDC egress (discovery,
# JWKS, token exchange) to IPs validated by Onetime::Http::Guard, closing
# the save-time-validate / request-time-re-resolve DNS-rebinding window.
#
# Covers:
# - install! propagates ONE shared block to OpenIDConnect, SWD, WebFinger
#   and Rack::OAuth2 (the gems that carry tenant-issuer OIDC traffic)
# - set-once semantics: a later http_config caller cannot displace the
#   pinning block; install! itself is idempotent
# - the propagation-skip hazard that makes install-first mandatory
# - ADAPTER_CONFIG behavior against a Net::HTTP double: pins ipaddr,
#   raises Guard::Blocked for blocked hosts, fails closed on a proxy
# - end-to-end through a gem-shaped Faraday connection (adapter declared
#   first, HTTP_CONFIG applied after — exactly what each gem's builder
#   does), under WebMock
#
# These are unit tests — no Valkey and no full app boot. The gems'
# http_config storage is process-global and set-once, so every example
# snapshots and restores it (see around hook) to avoid leaking the hook
# into sibling spec files that expect a pristine OpenIDConnect config.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/oidc_http_pinning_spec.rb

require_relative '../spec_helper'
require 'openid_connect'
require_relative '../../config/oidc_http_pinning'

RSpec.describe Auth::OidcHttpPinning do
  # Where each gem stores its http_config block. OpenIDConnect, SWD and
  # Rack::OAuth2 use a class variable; WebFinger (module_function) uses a
  # module-level instance variable. Kept here, not in the hook file: the
  # hook only ever writes through the public OpenIDConnect.http_config API.
  def http_config_stores
    [
      [OpenIDConnect, :cvar],
      [SWD,           :cvar],
      [Rack::OAuth2,  :cvar],
      [WebFinger,     :ivar],
    ]
  end

  def read_http_config(mod, kind)
    case kind
    when :cvar
      mod.class_variable_defined?(:@@http_config) ? mod.class_variable_get(:@@http_config) : nil
    when :ivar
      mod.instance_variable_get(:@http_config)
    end
  end

  def write_http_config(mod, kind, value)
    case kind
    when :cvar then mod.class_variable_set(:@@http_config, value)
    when :ivar then mod.instance_variable_set(:@http_config, value)
    end
  end

  def clear_http_configs
    http_config_stores.each { |mod, kind| write_http_config(mod, kind, nil) }
  end

  # http_config is set-once per process across four gems. Snapshot before
  # each example and restore after, so (a) examples are order-independent
  # and (b) whatever state the surrounding suite had — unset in a pure
  # unit run, installed when the full auth app booted first — is exactly
  # what it gets back.
  around do |example|
    saved = http_config_stores.map { |mod, kind| [mod, kind, read_http_config(mod, kind)] }
    begin
      example.run
    ensure
      saved.each { |mod, kind, value| write_http_config(mod, kind, value) }
    end
  end

  before { clear_http_configs }

  describe '.install!' do
    it 'propagates the same non-nil block to all four OIDC-traffic gems' do
      described_class.install!

      expect(OpenIDConnect.http_config).to eq(described_class::HTTP_CONFIG)
      expect(SWD.http_config).to eq(described_class::HTTP_CONFIG)
      expect(WebFinger.http_config).to eq(described_class::HTTP_CONFIG)
      expect(Rack::OAuth2.http_config).to eq(described_class::HTTP_CONFIG)
    end

    it 'is idempotent' do
      described_class.install!
      described_class.install!

      expect(OpenIDConnect.http_config).to eq(described_class::HTTP_CONFIG)
      expect(SWD.http_config).to eq(described_class::HTTP_CONFIG)
    end

    it 'cannot be displaced by a later http_config caller (set-once)' do
      described_class.install!

      interloper = ->(faraday) {}
      OpenIDConnect.http_config(&interloper)

      expect(OpenIDConnect.http_config).to eq(described_class::HTTP_CONFIG)
      expect(SWD.http_config).to eq(described_class::HTTP_CONFIG)
      expect(WebFinger.http_config).to eq(described_class::HTTP_CONFIG)
      expect(Rack::OAuth2.http_config).to eq(described_class::HTTP_CONFIG)
    end

    # OpenIDConnect.http_config propagates to sub-protocols with
    # `unless klass.http_config` — an already-configured gem is SKIPPED,
    # silently. This example documents WHY install! must be the first
    # http_config caller in the process: were anything to configure (say)
    # SWD before boot, discovery traffic through SWD would dial unpinned
    # while the other gems pin.
    it 'does not reach a sub-protocol that was configured first (install-first hazard)' do
      interloper = ->(faraday) {}
      SWD.http_config(&interloper)

      described_class.install!

      expect(SWD.http_config).to eq(interloper)
      expect(OpenIDConnect.http_config).to eq(described_class::HTTP_CONFIG)
      expect(WebFinger.http_config).to eq(described_class::HTTP_CONFIG)
      expect(Rack::OAuth2.http_config).to eq(described_class::HTTP_CONFIG)
    end
  end

  describe 'ADAPTER_CONFIG (per-request Net::HTTP hook)' do
    it 'pins the connection to the Guard-validated address for the target host' do
      http = instance_double(Net::HTTP, proxy_address: nil, address: 'idp.example.com')
      allow(Onetime::Http::Guard).to receive(:pinned_address!)
        .with('idp.example.com').and_return('203.0.113.7')

      expect(http).to receive(:ipaddr=).with('203.0.113.7')

      described_class::ADAPTER_CONFIG.call(http)
    end

    it 'raises Guard::Blocked for a blocked host before any connection is pinned' do
      # instance_double with no ipaddr= stub: any pin attempt after the
      # raise would itself fail the example.
      http = instance_double(Net::HTTP, proxy_address: nil, address: 'internal.evil.example')
      allow(Onetime::Http::Guard).to receive(:pinned_address!)
        .and_raise(Onetime::Http::Guard::Blocked, 'blocked address 169.254.169.254')

      expect {
        described_class::ADAPTER_CONFIG.call(http)
      }.to raise_error(Onetime::Http::Guard::Blocked, /blocked address/)
    end

    it 'fails closed when a forward proxy is configured, without resolving' do
      http = instance_double(Net::HTTP, proxy_address: '10.9.8.7', address: 'idp.example.com')
      allow(Onetime::Http::Guard).to receive(:pinned_address!)

      expect {
        described_class::ADAPTER_CONFIG.call(http)
      }.to raise_error(Onetime::Http::Guard::Blocked, /forward proxy/)

      expect(Onetime::Http::Guard).not_to have_received(:pinned_address!)
    end
  end

  describe 'HTTP_CONFIG through a gem-shaped Faraday connection' do
    # Build the connection the way OpenIDConnect/SWD/WebFinger/Rack::OAuth2
    # builders do: default adapter declared FIRST, http_config applied
    # after. Faraday 2's RackBuilder#adapter replaces rather than appends,
    # which is what lets HTTP_CONFIG's :net_http adapter win.
    def gem_shaped_connection(url)
      Faraday.new(url: url) do |faraday|
        faraday.adapter Faraday.default_adapter
        described_class::HTTP_CONFIG.call(faraday)
      end
    end

    it 'invokes the pinning hook with the target host on a real request path' do
      allow(Onetime::Http::Guard).to receive(:pinned_address!)
        .with('idp.example.com').and_return('203.0.113.7')
      stub = WebMock.stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      response = gem_shaped_connection('https://idp.example.com')
        .get('/.well-known/openid-configuration')

      expect(response.status).to eq(200)
      expect(Onetime::Http::Guard).to have_received(:pinned_address!).with('idp.example.com')
      expect(stub).to have_been_requested
    end

    it 'aborts a blocked host before the request is issued' do
      allow(Onetime::Http::Guard).to receive(:pinned_address!)
        .and_raise(Onetime::Http::Guard::Blocked, 'no A/AAAA records for rebound.example')
      stub = WebMock.stub_request(:get, 'https://rebound.example/token')
        .to_return(status: 200, body: '{}')

      expect {
        gem_shaped_connection('https://rebound.example').get('/token')
      }.to raise_error(Onetime::Http::Guard::Blocked)

      expect(stub).not_to have_been_requested
    end
  end
end
