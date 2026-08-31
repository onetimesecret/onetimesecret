# apps/web/auth/spec/unit/public_base_url_spec.rb
#
# frozen_string_literal: true

# Unit tests for the public-host `base_url` override (#4221) and its host
# allowlist (finding G-01).
#
# Rodauth composes every absolute URL from `base_url` → `domain` →
# `request.host`. Behind a Host-rewriting proxy that authority is the origin
# target; ungated, `request.host` also honors a client-supplied
# X-Forwarded-Host (Rack 3.2), so the stock value is BOTH wrong for
# custom-domain users AND poisonable by an attacker. The override swaps in the
# host DetectHost resolved for the request — but only when that host names a
# TXT-VERIFIED custom domain (Auth::PublicHost.served_custom_host?) — and
# otherwise falls back to the CANONICAL host, never request.host.
#
# Two subjects, because the policy and the wiring fail independently:
#   - Auth::PublicHost: which host, and when to decline (shared with the
#     OmniAuth full_host resolver — see omniauth_full_host_spec.rb).
#   - The Rodauth override: that `base_url` and `public_display_domain`
#     actually read that policy, through a real Rodauth configuration, and
#     fall back to the canonical host rather than the request authority.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/public_base_url_spec.rb

require_relative '../spec_helper'

require 'sequel'
require 'roda'
require 'rodauth'

# Define the Auth::Config namespace (normally provided by auth app boot).
# Auth::Config MUST be a Rodauth::Auth subclass here, never a plain module or
# class -- see the same preamble in omniauth_tenant_helpers_spec.rb for why a
# wrong constant type poisons boot for every later spec in the process.
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Overrides, Module.new) unless Auth::Config.const_defined?(:Overrides, false)

require_relative '../../config/overrides/public_base_url'

RSpec.describe Auth::Config::Overrides::PublicBaseUrl do
  # The canonical set and the tenant registry are process state loaded from
  # config / the datastore; stub the predicates so each example states its own
  # topology instead of depending on whatever the test environment happens to
  # hold.
  #
  #   - canonical_host?      : which hosts are in the canonical set
  #   - from_display_domain  : which hosts are registered custom domains, and
  #                            whether the record is TXT-verified (finding
  #                            G-01 requires a positive, VERIFIED record)
  #   - canonical_host /      : the request-independent canonical fallback the
  #     canonical_base_url       overrides use when the resolver declines
  before do
    allow(Onetime::Middleware::DomainStrategy)
      .to receive(:canonical_host?) { |host| canonical_hosts.include?(host.to_s) }

    allow(Onetime::CustomDomain).to receive(:from_display_domain) do |host|
      if verified_custom_hosts.include?(host.to_s)
        double('CustomDomain', verified: true)
      elsif unverified_custom_hosts.include?(host.to_s)
        double('CustomDomain', verified: false)
      end
    end

    allow(Auth::PublicHost).to receive(:canonical_host).and_return('onetimesecret.com')
    allow(Auth::PublicHost).to receive(:canonical_base_url).and_return('https://onetimesecret.com')
  end

  let(:canonical_hosts) { ['onetimesecret.com'] }
  let(:verified_custom_hosts) { ['secret.asi.nz', 'local-secrets4.afb.pet'] }
  let(:unverified_custom_hosts) { [] }

  # A Rack env in the shape DetectHost + DomainStrategy leave behind.
  #
  # @param host [String] the HTTP authority (what a rewriting proxy replaces)
  # @param display_domain [String, nil] env['onetime.display_domain']
  # @param scheme [String] forwarded scheme
  def env_for(host:, display_domain: nil, scheme: 'https', path: '/auth/login')
    env = Rack::MockRequest.env_for("#{scheme}://#{host}#{path}", 'HTTP_HOST' => host)
    env['HTTP_X_FORWARDED_PROTO'] = scheme
    env['onetime.display_domain'] = display_domain unless display_domain.nil?
    env
  end

  describe Auth::PublicHost do
    describe '.resolve' do
      it 'returns the display domain on a registered custom domain' do
        env = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz')
        expect(described_class.resolve(env)).to eq('secret.asi.nz')
      end

      it 'declines when the display domain is in the canonical set' do
        env = env_for(host: 'onetimesecret.com', display_domain: 'onetimesecret.com')
        expect(described_class.resolve(env)).to be_nil
      end

      it 'declines when the middleware did not run' do
        expect(described_class.resolve(env_for(host: 'example.com'))).to be_nil
      end

      # Finding G-01, vector A: display_domain is written for ANY syntactically
      # valid host, so a non-canonical host with no tenant record must NOT be
      # honored — otherwise a genuine service email links to an attacker origin.
      it 'declines a non-canonical host with no registered custom domain' do
        env = env_for(host: 'attacker.evil.example', display_domain: 'attacker.evil.example')
        expect(described_class.resolve(env)).to be_nil
      end

      # Registration is not ownership: anyone can create a record for a host
      # they don't control. Until the TXT challenge verifies, auth links must
      # stay on the canonical host.
      it 'declines a registered custom domain that is not TXT-verified' do
        unverified_custom_hosts << 'pending.tenant.example'
        env = env_for(host: 'nz.onetime.co', display_domain: 'pending.tenant.example')
        expect(described_class.resolve(env)).to be_nil
      end

      # Fail CLOSED: a datastore failure must never widen the accepted hosts.
      it 'declines (fails closed) when the tenant lookup raises' do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(Redis::BaseError.new('boom'))
        env = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz')
        expect(described_class.resolve(env)).to be_nil
      end
    end

    describe '.base_url' do
      it 'builds from the public host, never the rewritten authority' do
        env = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz')
        expect(described_class.base_url(env)).to eq('https://secret.asi.nz')
      end

      it 'preserves a non-default port' do
        env = env_for(host: 'localhost:7143', display_domain: 'local-secrets4.afb.pet',
                      scheme: 'http')
        expect(described_class.base_url(env)).to eq('http://local-secrets4.afb.pet:7143')
      end

      it 'follows the forwarded scheme when TLS terminates at the proxy' do
        env = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz')
        env['rack.url_scheme'] = 'http'
        expect(described_class.base_url(env)).to eq('https://secret.asi.nz')
      end

      it 'returns nil rather than a canonical URL when it declines' do
        expect(described_class.base_url(env_for(host: 'example.com'))).to be_nil
      end
    end
  end

  # Exercises the override the way Rodauth does: a real configuration, a real
  # request. The canonical fallback (finding G-01) replaces the former
  # `super()` fallback, so a canonical or unresolved request builds on the
  # canonical host — never on request.host.
  describe 'wired into a Rodauth configuration' do
    # rodauth's post_configure reads a Sequel connection even for routes that
    # never touch the database; nothing here queries it.
    let(:app) do
      db = Sequel.sqlite
      Class.new(Roda) do
        plugin :rodauth do
          enable :login
          db db
          Auth::Config::Overrides::PublicBaseUrl.configure(self)
        end

        route do |r|
          r.get 'probe' do
            "#{rodauth.base_url} #{rodauth.public_display_domain}"
          end
        end
      end
    end

    # @return [Array<String>] [base_url, public_display_domain]
    def probe(**opts)
      _status, _headers, body = app.call(env_for(path: '/probe', **opts))
      body.first.split(' ')
    end

    it 'mints links on the public host for a registered custom-domain request' do
      expect(probe(host: 'nz.onetime.co', display_domain: 'secret.asi.nz'))
        .to eq(['https://secret.asi.nz', 'secret.asi.nz'])
    end

    it 'builds on the canonical host, not request.host, on a canonical request' do
      expect(probe(host: 'onetimesecret.com', display_domain: 'onetimesecret.com'))
        .to eq(['https://onetimesecret.com', 'onetimesecret.com'])
    end

    it 'builds on the canonical host, not request.host, when the middleware did not run' do
      expect(probe(host: 'example.com')).to eq(['https://onetimesecret.com', 'onetimesecret.com'])
    end

    # Finding G-01, vector B: an attacker sets X-Forwarded-Host on a plain
    # canonical request. The override never reads request.host, so the link
    # must NOT carry the forged host regardless of any middleware.
    it 'ignores a forged X-Forwarded-Host and builds on the canonical host' do
      env = env_for(host: 'onetimesecret.com', display_domain: 'onetimesecret.com',
                    path: '/probe')
      env['HTTP_X_FORWARDED_HOST'] = 'attacker.example'
      _status, _headers, body = app.call(env)
      base_url, display_domain = body.first.split(' ')

      expect(base_url).to eq('https://onetimesecret.com')
      expect(display_domain).to eq('onetimesecret.com')
      expect(base_url).not_to include('attacker.example')
    end
  end
end
