# apps/web/auth/spec/unit/public_base_url_spec.rb
#
# frozen_string_literal: true

# Browser-origin allowlist and recipient-bound Rodauth credential email URLs.
# Run: tests/lanes/run unit --only apps/web/auth/spec/unit/public_base_url_spec.rb

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
    allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?) do |host|
      canonical_hosts.any? do |authority|
        Onetime::Utils::DomainParser.hostname_matches?(authority, host)
      end
    end
    allow(Onetime::Middleware::DomainStrategy)
      .to receive(:canonical_domains).and_return(canonical_hosts)

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

    describe '.webauthn_host and .webauthn_base_url' do
      it 'uses the classified public subdomain instead of a rewritten backend host' do
        env = env_for(host: 'app.internal', display_domain: 'eu.onetimesecret.com')
        env['onetime.domain_strategy'] = :subdomain

        expect(described_class.webauthn_host(env)).to eq('eu.onetimesecret.com')
        expect(described_class.webauthn_base_url(env)).to eq('https://eu.onetimesecret.com')
      end

      it 'uses the stashed custom-domain classification without another datastore lookup' do
        env = env_for(host: 'app.internal', display_domain: 'secret.asi.nz')
        env['onetime.domain_strategy'] = :custom
        env['onetime.custom_domain'] = double('CustomDomain')
        expect(Onetime::CustomDomain).not_to receive(:from_display_domain)

        expect(described_class.webauthn_host(env)).to eq('secret.asi.nz')
      end

      it 'refuses an unresolved custom or invalid classification' do
        unresolved = env_for(host: 'app.internal', display_domain: 'tenant.example')
        unresolved['onetime.domain_strategy'] = :custom
        invalid = env_for(host: 'app.internal', display_domain: 'attacker.example')
        invalid['onetime.domain_strategy'] = :invalid

        expect(described_class.webauthn_host(unresolved)).to be_nil
        expect(described_class.webauthn_host(invalid)).to be_nil
      end
    end

    describe '.canonical_request_host' do
      it 'returns a trusted candidate that is a member of the canonical set' do
        env = env_for(host: 'onetimesecret.com', display_domain: 'onetimesecret.com')
        expect(described_class.canonical_request_host(env)).to eq('onetimesecret.com')
      end

      it 'declines a non-canonical candidate (no widening past the allowlist)' do
        env = env_for(host: 'attacker.evil.example', display_domain: 'attacker.evil.example')
        expect(described_class.canonical_request_host(env)).to be_nil
      end

      # The raw authority is never a source: without a trusted candidate
      # (display_domain / DetectHost result) there is nothing to accept, even
      # when the Host header itself names a canonical host.
      it 'declines when the middleware left no trusted candidate' do
        expect(described_class.canonical_request_host(env_for(host: 'onetimesecret.com')))
          .to be_nil
      end

      # `canonical_host?` is port-INSENSITIVE, but the selected candidate is
      # resolved back to the trusted configured authority, including its port.
      it 'returns the configured canonical authority with its port' do
        canonical_hosts << 'localhost:7143'
        env = env_for(host: 'localhost:7143', display_domain: 'localhost:7143', scheme: 'http')
        expect(described_class.canonical_request_host(env)).to eq('localhost:7143')
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

    # Canonical candidates are matched port-insensitively, then resolved back
    # to the configured authority. Its explicit port takes precedence over the
    # request authority; without one, the existing request-port behavior stays.
    describe '.canonical_request_base_url' do
      it 'retains a configured non-default port with a doubled Host header' do
        canonical_hosts << 'localhost:7143'
        env = env_for(host: 'localhost:7143', display_domain: 'localhost', scheme: 'http')
        env['HTTP_HOST'] = 'localhost:7143, localhost:7143'

        expect(described_class.canonical_request_base_url(env)).to eq('http://localhost:7143')
      end

      it 'omits a configured scheme-default port instead of using the request port' do
        canonical_hosts.replace(['onetimesecret.com:443'])
        allow(described_class).to receive(:canonical_host).and_return('onetimesecret.com:443')
        env = env_for(host: 'onetimesecret.com:8443', display_domain: 'onetimesecret.com')

        expect(described_class.canonical_request_base_url(env)).to eq('https://onetimesecret.com')
      end

      it 'does not let a request-supplied port override the configured authority' do
        canonical_hosts << 'secrets.internal:8443'
        env = env_for(host: 'secrets.internal:9443', display_domain: 'secrets.internal:9443')

        expect(described_class.canonical_request_base_url(env)).to eq('https://secrets.internal:8443')
      end

      # RFC 3986 §3.2.2: the normalizer returns an IPv6 literal bare, and a
      # bare one cannot carry a port. Re-bracket before appending.
      it 'brackets an IPv6 literal so the authority stays parseable' do
        canonical_hosts << '[2001:db8::1]:7143'
        env = env_for(host: '[2001:db8::1]:7143', display_domain: '[2001:db8::1]:7143',
                      scheme: 'http')
        expect(described_class.canonical_request_base_url(env)).to eq('http://[2001:db8::1]:7143')
      end
    end

    # The one chain both consumers read (#4517): Rodauth's base_url override
    # and OmniAuth's full_host. Tier order is the contract; the raw authority
    # is never a tier.
    describe '.allowlisted_base_url' do
      it 'tier 1: builds on a verified tenant host with the request scheme and port' do
        env = env_for(host: 'localhost:7143', display_domain: 'secret.asi.nz', scheme: 'http')
        expect(described_class.allowlisted_base_url(env)).to eq('http://secret.asi.nz:7143')
      end

      it 'tier 2: builds on the request own canonical host with the request scheme and port' do
        canonical_hosts << 'eu.onetimesecret.com'
        env = env_for(host: 'origin.internal:8443', display_domain: 'eu.onetimesecret.com')
        expect(described_class.allowlisted_base_url(env)).to eq('https://eu.onetimesecret.com:8443')
      end

      it 'tier 3: builds on the configured canonical origin when no trusted candidate is allowlisted' do
        env = env_for(host: 'attacker.evil.example', display_domain: 'attacker.evil.example')
        expect(described_class.allowlisted_base_url(env)).to eq('https://onetimesecret.com')
      end

      it 'tier 3: builds on the configured canonical origin when the middleware did not run' do
        expect(described_class.allowlisted_base_url(env_for(host: 'example.com')))
          .to eq('https://onetimesecret.com')
      end

      it 'declines only when site.host is unconfigured too' do
        allow(described_class).to receive(:canonical_base_url).and_return(nil)
        expect(described_class.allowlisted_base_url(env_for(host: 'example.com'))).to be_nil
      end

      # #4517: a doubled Host reaches Rack verbatim once StripForwardedHost has
      # removed the forwarded header. It is not a source here.
      it 'never reads the raw authority', :aggregate_failures do
        env = env_for(host: 'onetimesecret.com', display_domain: 'onetimesecret.com')

        env['HTTP_HOST'] = 'onetimesecret.com, onetimesecret.com'
        expect(Rack::Request.new(env).base_url).to include(', ')
        expect(described_class.allowlisted_base_url(env)).to eq('https://onetimesecret.com')
      end
    end

    describe '.credential_base_url' do
      let(:env) { env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz') }
      let(:recipient) { { id: 7, external_id: 'recipient-extid' } }
      let(:organization) { instance_double(Onetime::Organization, objid: 'domain-org') }
      let(:customer) { instance_double(Onetime::Customer, objid: 'recipient-customer') }
      let(:domain) { instance_double(Onetime::CustomDomain, verified: true, primary_organization: organization) }
      let(:membership) { instance_double(Onetime::OrganizationMembership, active?: true, can_access_domain?: true) }

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('secret.asi.nz').and_return(domain)
        allow(Onetime::Customer).to receive(:find_by_extid).with('recipient-extid').and_return(customer)
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('domain-org', 'recipient-customer').and_return(membership)
      end

      it 'retains the tenant for the target account with active exact-domain authorization' do
        expect(described_class.credential_base_url(env, recipient)).to eq('https://secret.asi.nz')
        expect(membership).to have_received(:can_access_domain?).with(domain)
      end

      it 'uses the canonical origin when the recipient has no membership' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)
        expect(described_class.credential_base_url(env, recipient)).to eq('https://onetimesecret.com')
      end

      it 'uses the canonical origin for inactive membership' do
        allow(membership).to receive(:active?).and_return(false)
        expect(described_class.credential_base_url(env, recipient)).to eq('https://onetimesecret.com')
      end

      it 'uses the canonical origin for a sibling-domain membership' do
        allow(membership).to receive(:can_access_domain?).with(domain).and_return(false)
        expect(described_class.credential_base_url(env, recipient)).to eq('https://onetimesecret.com')
      end

      it 'does not use request or signup data in place of a recipient account' do
        expect(described_class.credential_base_url(env, nil)).to eq('https://onetimesecret.com')
        expect(described_class.credential_base_url(env, { email: 'recipient@example.com' }))
          .to eq('https://onetimesecret.com')
      end

      it 'uses canonical branding and origin when membership lookup fails' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_raise(Redis::BaseError, 'unavailable')
        expect(described_class.credential_base_url(env, recipient)).to eq('https://onetimesecret.com')
        expect(described_class.credential_display_host(env, recipient)).to eq('onetimesecret.com')
        expect(described_class.allowlisted_base_url(env)).to eq('https://secret.asi.nz')
      end

      it 'refuses an unbound recipient when no canonical origin is configured' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)
        allow(described_class).to receive(:canonical_base_url).and_return(nil)
        expect { described_class.required_credential_base_url!(env, recipient) }
          .to raise_error(described_class::MissingAllowlistedOrigin)
      end
    end

    describe '.allowlisted_host' do
      it 'follows the same tiers as .allowlisted_base_url', :aggregate_failures do
        tenant    = env_for(host: 'nz.onetime.co', display_domain: 'secret.asi.nz')
        canonical = env_for(host: 'onetimesecret.com', display_domain: 'onetimesecret.com')
        unknown   = env_for(host: 'attacker.evil.example', display_domain: 'attacker.evil.example')

        expect(described_class.allowlisted_host(tenant)).to eq('secret.asi.nz')
        expect(described_class.allowlisted_host(canonical)).to eq('onetimesecret.com')
        expect(described_class.allowlisted_host(unknown)).to eq('onetimesecret.com')
      end

      it 'declines only when site.host is unconfigured too' do
        allow(described_class).to receive(:canonical_host).and_return(nil)
        expect(described_class.allowlisted_host(env_for(host: 'example.com'))).to be_nil
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

    it 'uses canonical links for an unbound recipient even on a verified custom domain' do
      expect(probe(host: 'nz.onetime.co', display_domain: 'secret.asi.nz'))
        .to eq(['https://onetimesecret.com', 'onetimesecret.com'])
    end

    it 'builds on the canonical host, not request.host, on a canonical request' do
      expect(probe(host: 'onetimesecret.com', display_domain: 'onetimesecret.com'))
        .to eq(['https://onetimesecret.com', 'onetimesecret.com'])
    end

    # A split deployment: the request arrives on a SECONDARY canonical host
    # (link_domains / features.domains.default). Its links build on that host
    # — not rewritten to site.host — while the value still comes from the
    # trusted candidate, never request.host.
    it 'keeps a secondary canonical host on itself instead of rewriting to site.host' do
      canonical_hosts << 'eu.onetimesecret.com'
      expect(probe(host: 'eu.onetimesecret.com', display_domain: 'eu.onetimesecret.com'))
        .to eq(['https://eu.onetimesecret.com', 'eu.onetimesecret.com'])
    end

    it 'builds on the canonical host, not request.host, when the middleware did not run' do
      expect(probe(host: 'example.com')).to eq(['https://onetimesecret.com', 'onetimesecret.com'])
    end

    # The shape the full-auth E2E lane runs in (HOST=localhost:7143, SSL=false,
    # DOMAINS_ENABLED=false). Every `*_email_link` is `base_url` + a path, so a
    # doubled port here ships a dead link in the verification email.
    it 'mints a parseable link when the canonical host is configured with a port' do
      canonical_hosts << 'localhost:7143'
      base_url, display_domain =
        probe(host: 'localhost:7143', display_domain: 'localhost:7143', scheme: 'http')

      expect(base_url).to eq('http://localhost:7143')
      expect { URI.parse("#{base_url}/verify-account?key=abc") }.not_to raise_error
      expect(display_domain).to eq('localhost:7143')
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
