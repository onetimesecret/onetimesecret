# apps/web/auth/spec/unit/omniauth_full_host_spec.rb
#
# frozen_string_literal: true

# Unit tests for the public-host full_host resolver (#4224) and its host
# allowlist (finding G-01).
#
# `OmniAuth::Strategy#full_host` normally derives from `request.url` — Rack's
# authority — and every absolute URL the SSO flow hands an IdP is built from
# it: `callback_url` is `full_host + callback_path` (omniauth-entra-id defines
# it verbatim; the OAuth2 family inherits the shape), and the OIDC strategies
# read a `client_options.redirect_uri` the tenant hook composes from it.
#
# Behind a Host-rewriting proxy the authority is the origin target, so those
# URLs name a host the tenant's IdP has never seen. This resolver swaps in the
# public host — but ONLY when it names a registered custom domain
# (Auth::PublicHost.served_custom_host?) — and leaves every other request on
# OmniAuth's own derivation.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/omniauth_full_host_spec.rb

require_relative '../spec_helper'

# Define the Auth::Config namespace (normally provided by auth app boot).
# Auth::Config MUST be a Rodauth::Auth subclass here, never a plain module or
# class -- see the same preamble in omniauth_tenant_helpers_spec.rb for why a
# wrong constant type poisons boot for every later spec in the process.
require 'rodauth'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Features, Module.new) unless Auth::Config.const_defined?(:Features, false)

require_relative '../../config/features/omniauth'

RSpec.describe Auth::Config::Features::OmniAuth, '.full_host_for' do
  # The canonical set and the tenant registry are process state loaded from
  # config / the datastore; stub the predicates so each example states its own
  # topology. `from_display_domain` returns a record only for the hosts an
  # example declares registered — finding G-01 requires that positive evidence
  # before a host may root an SSO redirect_uri.
  before do
    allow(Onetime::Middleware::DomainStrategy)
      .to receive(:canonical_host?) { |host| canonical_hosts.include?(host.to_s) }

    allow(Onetime::CustomDomain).to receive(:from_display_domain) do |host|
      registered_custom_hosts.include?(host.to_s) ? Object.new : nil
    end
  end

  let(:canonical_hosts) { ['onetimesecret.com'] }
  let(:registered_custom_hosts) { ['secret.asi.nz', 'local-secrets4.afb.pet'] }

  # A Rack env in the shape DetectHost + DomainStrategy leave behind.
  #
  # @param host [String] the HTTP authority (what a rewriting proxy replaces)
  # @param display_domain [String, nil] env['onetime.display_domain']
  # @param strategy [Symbol, nil] env['onetime.domain_strategy']
  # @param scheme [String] forwarded scheme
  # @param detected_host [String, nil] DetectHost's result for this request
  def env_for(host:, display_domain: nil, strategy: nil, scheme: 'https', detected_host: nil)
    env = Rack::MockRequest.env_for(
      "#{scheme}://#{host}/auth/sso/entra",
      'HTTP_HOST' => host,
    )
    env['HTTP_X_FORWARDED_PROTO']   = scheme
    env['onetime.display_domain']   = display_domain unless display_domain.nil?
    env['onetime.domain_strategy']  = strategy unless strategy.nil?
    env[Rack::DetectHost.result_field_name] = detected_host unless detected_host.nil?
    env
  end

  context 'on a custom domain behind a Host-rewriting proxy' do
    # The production shape: Approximated puts the origin target in Host: and
    # carries the visitor's domain in Apx-Incoming-Host, which DetectHost
    # resolves into display_domain.
    let(:env) do
      env_for(
        host: 'nz.onetime.co',
        display_domain: 'secret.asi.nz',
        strategy: :custom,
      )
    end

    it 'builds the URL from the public host, not the rewritten authority' do
      expect(described_class.full_host_for(env)).to eq('https://secret.asi.nz')
    end

    it 'never names the origin target' do
      expect(described_class.full_host_for(env)).not_to include('nz.onetime.co')
    end
  end

  context 'on a custom domain behind a proxy that preserves Host' do
    # Our own ingress: the customer CNAMEs to us and Caddy passes Host through,
    # so DetectHost resolves the same value from the Host header itself. The
    # resolver must be a no-op here — this is the topology most installs run.
    it 'returns the same host the request already carried' do
      env = env_for(
        host: 'secret.asi.nz',
        display_domain: 'secret.asi.nz',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://secret.asi.nz')
    end
  end

  context 'when the domains feature is off' do
    # DomainStrategy skips host classification wholesale and pins
    # display_domain to the canonical host, so that value says nothing about
    # this request -- but DetectHost still ran, and still holds the host the
    # browser used. When that detected host is a REGISTERED custom domain the
    # resolver honors it; the redirect_uri must not name the origin target.
    it 'builds from the detected host when it is a registered custom domain' do
      # Only the hostname is swapped: scheme and port still come from the
      # request, so the origin's :3000 rides along. That is the documented
      # composition (see full_host_for) and the forwarded-port question is
      # tracked separately in #4223.
      env = env_for(
        host: '127.0.0.1:3000',
        display_domain: 'onetimesecret.com',
        strategy: :canonical,
        detected_host: 'secret.asi.nz',
        scheme: 'http',
      )

      expect(described_class.full_host_for(env)).to eq('http://secret.asi.nz:3000')
    end

    it 'is a no-op when the detected host is itself canonical' do
      env = env_for(
        host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        strategy: :canonical,
        detected_host: 'onetimesecret.com',
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end
  end

  context 'when the display domain is a canonical host' do
    # DomainStrategy pins display_domain to the canonical host on two paths
    # that say nothing about where the browser is -- the domains feature being
    # off, and a detected host failing validation. Honoring it there would
    # bounce the visitor to a different host mid-flow.
    it 'keeps the request authority on a genuine canonical request' do
      env = env_for(
        host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        strategy: :canonical,
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    it 'does not redirect a local unrecognized host to the pinned canonical' do
      # DetectHost rejects localhost, so DomainStrategy substitutes the
      # canonical host. Local development must keep working on its own port.
      env = env_for(
        host: 'localhost:3000',
        display_domain: 'onetimesecret.com',
        strategy: :invalid,
        scheme: 'http',
      )

      expect(described_class.full_host_for(env)).to eq('http://localhost:3000')
    end

    it 'treats a split deployment second canonical host as canonical' do
      # features.domains.default anchors links while site.host serves the app;
      # both are in the canonical set and neither is a tenant.
      env = env_for(
        host: 'app.onetimesecret.com',
        display_domain: 'app.onetimesecret.com',
        strategy: :canonical,
      )
      allow(Onetime::Middleware::DomainStrategy)
        .to receive(:canonical_host?).with('app.onetimesecret.com').and_return(true)

      expect(described_class.full_host_for(env)).to eq('https://app.onetimesecret.com')
    end

    it 'keeps the request authority when the middleware did not run' do
      env = env_for(host: 'example.com')

      expect(described_class.full_host_for(env)).to eq('https://example.com')
    end
  end

  context 'when the host is non-canonical but not a registered tenant' do
    # Finding G-01, vector A: display_domain / the detected host are written
    # for ANY syntactically valid host. Without a CustomDomain record we must
    # NOT root the redirect_uri on it — it would hand the IdP an attacker
    # origin. full_host_for keeps OmniAuth's own (request) derivation.
    it 'does not honor an unregistered display domain' do
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'attacker.evil.example',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://nz.onetime.co')
    end

    it 'fails closed when the tenant lookup raises' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .and_raise(Redis::BaseError.new('boom'))
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'secret.asi.nz',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://nz.onetime.co')
    end
  end

  context 'when the classification degraded but the host did not' do
    # Chooserator wraps its whole chain in a rescue, so a datastore blip -- or
    # an unparseable canonical host, which is what the integration environment
    # actually has -- classifies a real customer domain :invalid while
    # display_domain stays correct. The resolver keys on the tenant RECORD, not
    # the classification, so a registered domain still builds from its own host
    # in exactly that window.
    it 'still builds from the public host when the strategy is :invalid' do
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'secret.asi.nz',
        strategy: :invalid,
      )

      expect(described_class.full_host_for(env)).to eq('https://secret.asi.nz')
    end
  end

  describe 'authority composition' do
    it 'preserves a non-default port' do
      env = env_for(
        host: 'local-secrets4.afb.pet:7143',
        display_domain: 'local-secrets4.afb.pet',
        strategy: :custom,
        scheme: 'http',
      )

      expect(described_class.full_host_for(env)).to eq('http://local-secrets4.afb.pet:7143')
    end

    it 'omits the default port for the scheme' do
      env = env_for(
        host: 'secret.asi.nz:443',
        display_domain: 'secret.asi.nz',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://secret.asi.nz')
    end

    it 'follows the forwarded scheme when TLS terminates at the proxy' do
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'secret.asi.nz',
        strategy: :custom,
        scheme: 'https',
      )
      env['rack.url_scheme'] = 'http' # origin hop is plaintext

      expect(described_class.full_host_for(env)).to eq('https://secret.asi.nz')
    end
  end

  describe '.public_host_for' do
    it 'returns the display domain on a registered custom domain' do
      env = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz', strategy: :custom)

      expect(described_class.public_host_for(env)).to eq('secret.asi.nz')
    end

    it 'returns nil when the display domain is in the canonical set' do
      env = env_for(host: 'onetimesecret.com', display_domain: 'onetimesecret.com', strategy: :canonical)

      expect(described_class.public_host_for(env)).to be_nil
    end

    it 'returns nil when the display domain is blank' do
      env = env_for(host: 'nz.onetime.co', display_domain: '', strategy: :custom)

      expect(described_class.public_host_for(env)).to be_nil
    end

    it 'returns nil for a non-canonical host with no registered tenant record' do
      env = env_for(host: 'nz.onetime.co', display_domain: 'attacker.evil.example', strategy: :custom)

      expect(described_class.public_host_for(env)).to be_nil
    end

    it 'falls through to the detected host when the display domain is canonical' do
      env = env_for(
        host: '127.0.0.1:3000',
        display_domain: 'onetimesecret.com',
        detected_host: 'secret.asi.nz',
      )

      expect(described_class.public_host_for(env)).to eq('secret.asi.nz')
    end

    it 'prefers a resolved display domain over the detected host' do
      # request.host and DetectHost can both be poisoned by a client-supplied
      # X-Forwarded-Host in a topology the edge does not sanitize; a registered
      # display_domain is DomainStrategy's validated answer.
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'secret.asi.nz',
        detected_host: 'spoofed.example.com',
      )

      expect(described_class.public_host_for(env)).to eq('secret.asi.nz')
    end

    it 'returns nil when neither middleware resolved a registered custom host' do
      env = env_for(host: 'localhost:3000', display_domain: 'onetimesecret.com', scheme: 'http')

      expect(described_class.public_host_for(env)).to be_nil
    end
  end

  describe '.install_public_host_full_host!' do
    around do |example|
      previous = ::OmniAuth.config.full_host
      example.run
      ::OmniAuth.config.full_host = previous
    end

    it 'installs a Proc so OmniAuth resolves it per request' do
      ::OmniAuth.config.full_host = nil
      described_class.install_public_host_full_host!

      # OmniAuth::Strategy#full_host only calls it when it is a Proc; a String
      # would freeze one host for the whole process.
      expect(::OmniAuth.config.full_host).to be_a(Proc)
    end

    it 'resolves the public host through the installed Proc' do
      described_class.install_public_host_full_host!
      env = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz', strategy: :custom)

      expect(::OmniAuth.config.full_host.call(env)).to eq('https://secret.asi.nz')
    end
  end
end
