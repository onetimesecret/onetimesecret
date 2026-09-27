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
# public host — but ONLY when it names a TXT-verified custom domain
# (Auth::PublicHost.served_custom_host?) — and builds every other request on
# the canonical tiers Rodauth's `base_url` override already uses (the
# request's own canonical host, then the configured site.host), never on the
# raw authority (#4517). Rack's derivation is reached only when site.host is
# unconfigured.
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
  # example declares registered, carrying its TXT-verification state — finding
  # G-01 requires a positive, VERIFIED record before a host may root an SSO
  # redirect_uri.
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

    # The configured canonical host (site.host / site.ssl), the
    # request-independent tier the chain ends on.
    allow(Auth::PublicHost).to receive_messages(
      canonical_host: configured_host,
      canonical_base_url: configured_base_url,
    )
  end

  let(:configured_host) { 'onetimesecret.com' }
  let(:configured_base_url) { 'https://onetimesecret.com' }
  let(:canonical_hosts) { ['onetimesecret.com'] }
  let(:verified_custom_hosts) { ['secret.asi.nz', 'local-secrets4.afb.pet'] }
  let(:unverified_custom_hosts) { [] }

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
    # DomainStrategy pins display_domain to the canonical host whenever the
    # domains feature is off or the detected host fails validation. Either
    # way the request is served AS the canonical host, and that -- not the
    # raw authority -- is what the URL builds on (the canonical_request tier
    # Rodauth's base_url override has always used).
    it 'builds on the canonical host on a genuine canonical request' do
      env = env_for(
        host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        strategy: :canonical,
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    it 'builds on the pinned canonical host, with the request port, for a local unrecognized host' do
      # DetectHost rejects localhost, so DomainStrategy substitutes the
      # canonical host. A browser on a host OTHER than site.host gets its SSO
      # URLs on site.host -- the same host its email links already build on
      # -- rather than on the raw authority. Configured local development
      # (site.host = the host the browser is on) is the next example.
      env = env_for(
        host: 'localhost:3000',
        display_domain: 'onetimesecret.com',
        strategy: :invalid,
        scheme: 'http',
      )

      expect(described_class.full_host_for(env)).to eq('http://onetimesecret.com:3000')
    end

    it 'keeps a local development host that is itself site.host' do
      # The full-auth E2E lane and every dev setup: HOST=localhost:7143,
      # domains off, browser on localhost:7143. display_domain is pinned to
      # site.host WITH its port; the URL must not double it.
      canonical_hosts << 'localhost:7143'
      env = env_for(
        host: 'localhost:7143',
        display_domain: 'localhost:7143',
        strategy: :canonical,
        scheme: 'http',
      )

      expect(described_class.full_host_for(env)).to eq('http://localhost:7143')
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

    it 'builds on the configured canonical host when the middleware did not run' do
      # No trusted candidate at all: the raw authority is still not a source.
      env = env_for(host: 'example.com')

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    it 'falls to the request authority only when site.host is unconfigured' do
      # The one place Rack's derivation survives: the "must set site.host"
      # misconfiguration, the same last resort Rodauth's super() covers.
      allow(Auth::PublicHost).to receive_messages(canonical_host: nil, canonical_base_url: nil)
      env = env_for(host: 'example.com')

      expect(described_class.full_host_for(env)).to eq('https://example.com')
    end
  end

  context 'when a proxy sends a doubled Host header (#4517)' do
    # `proxy_set_header Host $host` layered on a `Host:` the client already
    # sent, or two proxies each appending one, reaches Rack as
    # `Host: a, a`. StripForwardedHost (#4319) removes X-Forwarded-Host at
    # the stack edge, so Rack::Request#base_url returns that value verbatim:
    # `https://a, a`. DetectHost keeps the FIRST comma-separated element
    # (lib/middleware/detect_host.rb normalize_host) — or nothing, when
    # site.host is an IP literal, which DetectHost never accepts — and
    # DomainStrategy pins display_domain to the canonical host either way:
    # it copies canonical_domain with the domains feature off and classifies
    # the kept element :canonical with it on. The redirect_uri must build on
    # THAT, not on the authority. The fix does not rely on DetectHost
    # rejecting the doubled value.
    def doubled_host_env(display_domain:, strategy:, host: 'onetimesecret.com', detected_host: nil, scheme: 'https')
      env = env_for(
        host: host,
        display_domain: display_domain,
        strategy: strategy,
        detected_host: detected_host,
        scheme: scheme,
      )

      env['HTTP_HOST'] = "#{host}, #{host}"
      env
    end

    it 'is the shape Rack hands back verbatim (documents the defect)' do
      env = doubled_host_env(display_domain: 'onetimesecret.com', strategy: :canonical)

      expect(Rack::Request.new(env).base_url).to eq('https://onetimesecret.com, onetimesecret.com')
    end

    it 'builds the redirect_uri on the canonical host, never the doubled authority' do
      # Hostname site.host with the domains feature on: DetectHost kept
      # 'onetimesecret.com' from the doubled value and DomainStrategy
      # classified it :canonical.
      env = doubled_host_env(
        display_domain: 'onetimesecret.com',
        strategy: :canonical,
        detected_host: 'onetimesecret.com',
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    it 'does the same when the domains feature is off and site.host carries its port' do
      # The reporter's topology (#4499): domains disabled, platform SSO on
      # site.host. DomainStrategy copies site.host into display_domain
      # verbatim, port included, and still writes strategy :canonical. The
      # port must neither double nor leak through the doubled-Host path.
      canonical_hosts << 'onetimesecret.com:443'
      env = doubled_host_env(
        display_domain: 'onetimesecret.com:443',
        strategy: :canonical,
        detected_host: 'onetimesecret.com',
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    it 'does the same for an IP-literal site.host, which DetectHost never accepts' do
      # rack.detected_host is nil here; DomainStrategy still pins
      # display_domain to the canonical host.
      canonical_hosts << '127.0.0.1'
      env = doubled_host_env(host: '127.0.0.1', display_domain: '127.0.0.1', strategy: :canonical, scheme: 'http')

      expect(described_class.full_host_for(env)).to eq('http://127.0.0.1')
    end

    it 'drops a non-default port from site.host, because the doubled authority is unparseable' do
      # Tier 2 (canonical_request_base_url) wins here and composes the origin
      # through origin_for, which reads the port from Rack::Request#port.
      # Rack cannot parse `secrets.internal:8443, secrets.internal:8443`, so
      # it reports the scheme's default port and the origin omits 8443: an
      # IdP registered with the ported callback still rejects the login. The
      # port comes from the request authority (or X-Forwarded-Port), never
      # from the allowlisted candidate, so a ported site.host behind a
      # doubling proxy still needs the proxy fixed. Pinned so the gap stays
      # visible; a fix belongs in origin_for and touches every Rodauth link.
      canonical_hosts << 'secrets.internal:8443'
      env = doubled_host_env(
        host: 'secrets.internal:8443',
        display_domain: 'secrets.internal:8443',
        strategy: :canonical,
        detected_host: 'secrets.internal',
      )

      expect(described_class.full_host_for(env)).to eq('https://secrets.internal')
    end

    it 'agrees with the Rodauth email-link origin for the same request' do
      env = doubled_host_env(display_domain: 'onetimesecret.com', strategy: :canonical)

      expect(described_class.full_host_for(env)).to eq(Auth::PublicHost.allowlisted_base_url(env))
    end
  end

  context 'when the host is non-canonical but not a registered tenant' do
    # Finding G-01, vector A: display_domain / the detected host are written
    # for ANY syntactically valid host. Without a CustomDomain record we must
    # NOT root the redirect_uri on it — it would hand the IdP an attacker
    # origin. Nor on the origin target: the chain falls through to the
    # configured canonical host, the same way an email link for this request
    # does.
    it 'does not honor an unregistered display domain' do
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'attacker.evil.example',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    # Registration is not ownership: until the TXT challenge verifies, the
    # redirect_uri must not be rooted on the record's host.
    it 'does not honor a registered custom domain that is not TXT-verified' do
      unverified_custom_hosts << 'pending.tenant.example'
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'pending.tenant.example',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
    end

    it 'fails closed to the canonical host when the tenant lookup raises' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .and_raise(Redis::BaseError.new('boom'))
      env = env_for(
        host: 'nz.onetime.co',
        display_domain: 'secret.asi.nz',
        strategy: :custom,
      )

      expect(described_class.full_host_for(env)).to eq('https://onetimesecret.com')
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
