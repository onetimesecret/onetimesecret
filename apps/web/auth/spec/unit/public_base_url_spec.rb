# apps/web/auth/spec/unit/public_base_url_spec.rb
#
# frozen_string_literal: true

# Unit tests for the public-host `base_url` override (#4221).
#
# Rodauth composes every absolute URL from `base_url` → `domain` →
# `request.host`. Behind a Host-rewriting proxy that authority is the origin
# target, so a custom-domain user asking for a magic link receives a link to
# the canonical host — where Auth::SigninGate 404s :email_auth on any install
# whose global signin is off. The override swaps in the host DetectHost
# resolved for the request, and only when it resolved one.
#
# Two subjects, because the policy and the wiring fail independently:
#   - Auth::PublicHost: which host, and when to decline (shared with the
#     OmniAuth full_host resolver — see omniauth_full_host_spec.rb).
#   - The Rodauth override: that `base_url` and `public_display_domain`
#     actually read that policy, through a real Rodauth configuration.
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
  # The canonical set is process state loaded from config; stub the predicate
  # so each example states its own topology instead of depending on whatever
  # the test config's canonical host happens to be.
  before do
    allow(Onetime::Middleware::DomainStrategy)
      .to receive(:canonical_host?) { |host| canonical_hosts.include?(host.to_s) }
  end

  let(:canonical_hosts) { ['onetimesecret.com'] }

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
      it 'returns the display domain on a custom domain' do
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
  # request. Guards the `super()` fallback specifically — a bare `super` in a
  # define_method body raises at call time, not at load, so only calling it
  # proves the canonical path still works.
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

    it 'mints links on the public host for a custom-domain request' do
      expect(probe(host: 'nz.onetime.co', display_domain: 'secret.asi.nz'))
        .to eq(['https://secret.asi.nz', 'secret.asi.nz'])
    end

    it 'falls through to Rodauth on a canonical request' do
      expect(probe(host: 'onetimesecret.com', display_domain: 'onetimesecret.com'))
        .to eq(['https://onetimesecret.com', 'onetimesecret.com'])
    end

    it 'falls through to Rodauth when the middleware did not run' do
      expect(probe(host: 'example.com')).to eq(['https://example.com', 'example.com'])
    end
  end
end
