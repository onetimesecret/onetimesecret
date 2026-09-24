# spec/unit/onetime/sso_provider/registry_spec.rb
#
# frozen_string_literal: true

# Shape validation for Onetime::SsoProvider::Registry — the single source of
# truth for SSO provider wiring (serializer gating, CSP origins, and
# boot-time strategy registration all read it).
#
# These specs are the guard rail for ADDING a provider: a new entry that
# is missing a field, reuses a route name, or mixes up its env prefix
# fails here before it can half-register at boot.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit

require 'spec_helper'
require 'climate_control'
require_relative '../../../../lib/onetime/sso_provider/registry'
require_relative '../../../support/saml/test_idp'

RSpec.describe Onetime::SsoProvider::Registry do
  let(:definitions) { described_class::DEFINITIONS }

  # A SAML-compatible session cookie: Saml.platform_options checks it before
  # anything else (#4450), and the unit lane's config carries the shipped
  # same_site: lax. The rule itself is pinned under 'the session cookie'.
  before do
    allow(Onetime).to receive(:session_config).and_return('same_site' => 'none', 'secure' => true)
  end

  REQUIRED_FIELDS = [
    :key, :label, :strategy, :gem_require, :issuer_capable, :required_vars, :route_var, :route_default, :display_var, :display_default, :trust_var, :trust_default, :placeholder_options, :strategy_options
  ].freeze

  it 'defines at least the four launch providers' do
    expect(definitions.map { |d| d[:key] }).to include(:oidc, :entra, :google, :github)
  end

  it 'gives every definition the full field set' do
    definitions.each do |defn|
      missing = REQUIRED_FIELDS.reject { |field| defn.key?(field) }
      expect(missing).to be_empty,
        "definition #{defn[:key].inspect} is missing fields: #{missing.inspect}"
    end
  end

  it 'uses unique keys and unique default route names' do
    keys   = definitions.map { |d| d[:key] }
    routes = definitions.map { |d| d[:route_default] }
    expect(keys).to eq(keys.uniq)
    expect(routes).to eq(routes.uniq)
  end

  it 'types every field correctly' do
    definitions.each do |defn|
      expect(defn[:key]).to be_a(Symbol)
      expect(defn[:label]).to be_a(String)
      expect(defn[:strategy]).to be_a(Symbol)
      expect(defn[:gem_require]).to be_a(String)
      expect(defn[:issuer_capable]).to be(true).or be(false)
      expect(defn[:required_vars]).to all(be_a(String))
      expect(defn[:required_vars]).not_to be_empty
      expect(defn[:placeholder_options]).to be_a(Hash)
      expect(defn[:strategy_options]).to respond_to(:call)
      expect(defn[:trust_default]).to be(true).or be(false)
    end
  end

  it 'keeps env var names on a consistent per-provider prefix' do
    definitions.each do |defn|
      # The prefix is derived from the route/display/trust vars, which must
      # all agree (required_vars may differ, e.g. OIDC's ISSUER var).
      prefix = defn[:route_var].delete_suffix('_ROUTE_NAME')
      expect(defn[:display_var]).to eq("#{prefix}_DISPLAY_NAME")
      expect(defn[:trust_var]).to eq("#{prefix}_TRUST_EMAIL_FOR_LINKING")
    end
  end

  it 'gives every definition exactly one CSP origin source' do
    definitions.each do |defn|
      sources = [defn[:idp_origin], defn[:idp_origin_from]].compact
      expect(sources.length).to eq(1),
        "definition #{defn[:key].inspect} must set exactly one of idp_origin/idp_origin_from"
    end
  end

  it 'requires any idp_origin_from var to be in required_vars' do
    # The CSP origin gate and the sso_providers gate share required_vars; an
    # idp_origin_from var outside that list could emit a CSP origin for a
    # provider whose serializer gating never checks the same var.
    definitions.each do |defn|
      next unless defn[:idp_origin_from]

      expect(defn[:required_vars]).to include(defn[:idp_origin_from]),
        "definition #{defn[:key].inspect}: idp_origin_from #{defn[:idp_origin_from].inspect} " \
        'must be one of its required_vars'
    end
  end

  it 'never uses real-looking credentials in placeholder_options' do
    definitions.each do |defn|
      defn[:placeholder_options].each do |opt, value|
        next unless [:client_id, :client_secret, :tenant_id].include?(opt)

        expect(value).to eq('placeholder'),
          "definition #{defn[:key].inspect} placeholder option #{opt} must be 'placeholder'"
      end
    end
  end

  it 'freezes the registry and every definition' do
    expect(definitions).to be_frozen
    expect(definitions).to all(be_frozen)
  end

  describe '.find' do
    it 'returns the definition for a known key' do
      expect(described_class.find(:entra)[:strategy]).to eq(:entra_id)
    end

    it 'returns nil for an unknown key instead of raising' do
      # AuthConfig#tenant_idp_origin resolves a PROVIDER_ROUTE_MAP route name
      # through here per request, inside the CSP middleware, where a KeyError
      # would 500 the response.
      expect(described_class.find(:facebook)).to be_nil
    end
  end

  describe '.fetch' do
    it 'returns the definition for a known key' do
      expect(described_class.fetch(:oidc)[:strategy]).to eq(:openid_connect)
    end

    it 'raises KeyError for an unknown key' do
      expect { described_class.fetch(:facebook) }.to raise_error(KeyError, /facebook/)
    end

    it 'delegates the lookup to .find (one predicate, no second copy)' do
      allow(described_class).to receive(:find).and_call_original
      described_class.fetch(:oidc)
      expect(described_class).to have_received(:find).with(:oidc)
    end
  end

  describe 'strategy_options' do
    it 'builds options from the env without raising when vars are present' do
      ClimateControl.modify(
        OIDC_ISSUER: 'https://idp.example.com',
        OIDC_CLIENT_ID: 'cid',
        OIDC_CLIENT_SECRET: '',
        ENTRA_TENANT_ID: 'tid',
        ENTRA_CLIENT_ID: 'cid',
        ENTRA_CLIENT_SECRET: 'cs',
        GOOGLE_CLIENT_ID: 'cid',
        GOOGLE_CLIENT_SECRET: 'cs',
        GITHUB_CLIENT_ID: 'cid',
        GITHUB_CLIENT_SECRET: 'cs',
        APPLE_CLIENT_ID: 'com.example.web',
        APPLE_TEAM_ID: 'TEAM123456',
        APPLE_KEY_ID: 'KEY1234567',
        APPLE_PRIVATE_KEY: "-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n",
        SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com/saml/sso',
        SAML_IDP_ENTITY_ID: 'https://idp.example.com/saml/metadata',
        SAML_IDP_CERT: SamlSpec::TestIdp.new.cert_pem,
        SAML_SP_ENTITY_ID: 'https://ots.example.com/auth/sso/saml/metadata',
      ) do
        definitions.each do |defn|
          expect(defn[:strategy_options].call).to be_a(Hash)
        end
      end
    end

    # :vars_valid is opt-in — a definition without it is presence-only and
    # always valid once required_vars are present. Exactly the definitions
    # whose strategy_options can RAISE carry one (see the registry header),
    # so the advertised and registered sets cannot disagree. SAML is the only
    # such definition today (see the SAML block below).
    it 'is carried only by the SAML definition' do
      with_predicate = described_class::DEFINITIONS.select { |defn| defn[:vars_valid] }
      expect(with_predicate.map { |defn| defn[:key] }).to eq([:saml])
    end

    # Deployments routinely carry multi-line secrets as a single line with
    # literal backslash-n. OpenSSL::PKey::EC cannot parse that, and the
    # failure would surface as a per-request client-secret error at the Apple
    # request phase rather than at boot.
    it 'un-escapes a backslash-n encoded Apple private key' do
      ClimateControl.modify(APPLE_PRIVATE_KEY: '-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n') do
        opts = described_class.fetch(:apple)[:strategy_options].call
        expect(opts[:pem]).to eq("-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n")
      end
    end

    it 'leaves an already multi-line Apple private key untouched' do
      pem = "-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n"
      ClimateControl.modify(APPLE_PRIVATE_KEY: pem) do
        opts = described_class.fetch(:apple)[:strategy_options].call
        expect(opts[:pem]).to eq(pem)
      end
    end

    # resolve_issuer precedence #1 reads this option. Apple's strategy
    # hard-codes the same constant in verify_iss!, so a row can only exist if
    # Apple itself asserted it — but the strategy nests the claim under
    # extra.raw_info.id_info with symbol keys, which the token-issuer branch
    # does not read. Dropping this option would silently collapse Apple to the
    # '' sentinel and make it issuerless.
    it 'declares the Apple issuer so resolve_issuer does not fall through' do
      opts = described_class.fetch(:apple)[:strategy_options].call
      expect(opts[:issuer]).to eq('https://appleid.apple.com')
    end

    it 'omits the OIDC client secret when blank (PKCE-only flows)' do
      ClimateControl.modify(OIDC_CLIENT_ID: 'cid', OIDC_CLIENT_SECRET: '') do
        opts = described_class.fetch(:oidc)[:strategy_options].call
        expect(opts[:client_options]).not_to have_key(:secret)
      end
    end

    # ========================================================================
    # SAML (#4450)
    # ========================================================================
    describe 'the SAML definition' do
      let(:saml) { described_class.fetch(:saml) }
      let(:idp) { SamlSpec::TestIdp.new }
      let(:valid_env) do
        {
          SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com/saml/sso',
          SAML_IDP_ENTITY_ID: 'https://idp.example.com/saml/metadata',
          SAML_IDP_CERT: idp.cert_pem,
          SAML_SP_ENTITY_ID: 'https://ots.example.com/auth/sso/saml/metadata',
          SAML_UID_ATTRIBUTE: nil,
          SAML_ROUTE_NAME: nil,
        }
      end

      def saml_options(overrides = {})
        ClimateControl.modify(valid_env.merge(overrides)) { saml[:strategy_options].call }
      end

      def saml_valid?(overrides = {})
        ClimateControl.modify(valid_env.merge(overrides)) { saml[:vars_valid].call }
      end

      # THE assertion this block exists for. In ruby-saml `issuer` is a
      # deprecated alias for OUR SP EntityID (settings.rb:121-122), and
      # resolve_issuer precedence #1 reads strategy option :issuer — so an
      # `issuer:` key, the pattern Apple legitimately uses, would key
      # every SAML identity on this deployment's own EntityID and collapse
      # every IdP into one issuer namespace. String key checked too: options
      # end up in a Mash.
      it 'NEVER declares an :issuer strategy option, real or placeholder' do
        [saml_options, saml[:placeholder_options]].each do |opts|
          expect(opts).not_to have_key(:issuer)
          expect(opts).not_to have_key('issuer')
        end
      end

      it 'names the in-repo strategy subclass, loaded through its own file' do
        expect(saml[:strategy]).to eq(:request_bound_saml)
        expect(saml[:gem_require]).to eq('onetime/sso_provider/request_bound_saml')
        expect(saml[:issuer_capable]).to be true
      end

      # SAML has no client credential. The registry's naming rule is about the
      # ROUTE/DISPLAY/TRUST prefix (asserted for every definition above);
      # there is deliberately no SAML_CLIENT_ID to satisfy a convention.
      it 'requires exactly the IdP trio, all SAML_-prefixed, with no client credential' do
        expect(saml[:required_vars]).to eq(%w[SAML_IDP_SSO_SERVICE_URL SAML_IDP_ENTITY_ID SAML_IDP_CERT])
        expect(saml[:required_vars]).to all(start_with('SAML_'))
        expect(saml[:required_vars].grep(/CLIENT/)).to be_empty
      end

      # The browser is redirected to — and posts the response back from — the
      # SSO service URL's origin. An EntityID is an opaque name (often a URN).
      it 'derives the CSP / HttpOrigin origin from the SSO service URL, not the EntityID' do
        expect(saml[:idp_origin_from]).to eq('SAML_IDP_SSO_SERVICE_URL')
      end

      # omniauth-saml calls Settings.new(options) without
      # keep_security_attributes, so this hash REPLACES ruby-saml's defaults:
      # a key missing here is nil at validation time. Asserted key by key, and
      # as an exact key set, so neither a dropped nor an added key passes.
      it 'passes the FULL ruby-saml security hash, key by key' do
        expect(saml_options[:security]).to eq(
          authn_requests_signed: false,
          logout_requests_signed: false,
          logout_responses_signed: false,
          want_assertions_signed: true,
          want_assertions_encrypted: false,
          want_name_id: true,
          metadata_signed: false,
          embed_sign: false,
          digest_method: 'http://www.w3.org/2001/04/xmlenc#sha256',
          signature_method: 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
          check_idp_cert_expiration: true,
          check_sp_cert_expiration: false,
          strict_audience_validation: true,
          lowercase_url_encoding: false,
        )
      end

      # RE-VERIFY on a ruby-saml bump: the literals in saml.rb (written as
      # literals so the registry loads without the gem) must be the gem's own
      # constants, and the security hash must cover every key ruby-saml
      # defaults — a NEW default key in a later release would otherwise be nil.
      it 'matches ruby-saml: algorithm constants, and every default security key is covered' do
        require 'onelogin/ruby-saml'

        expect(Onetime::SsoProvider::Saml::DIGEST_SHA256).to eq(XMLSecurity::Document::SHA256)
        expect(Onetime::SsoProvider::Saml::SIGNATURE_RSA_SHA256).to eq(XMLSecurity::Document::RSA_SHA256)

        gem_keys = OneLogin::RubySaml::Settings::DEFAULTS[:security].keys
        expect(Onetime::SsoProvider::Saml::SECURITY.keys).to match_array(gem_keys)
      end

      # Response options, not Settings accessors: they work only at the top
      # level (omniauth-saml forwards Response::AVAILABLE_OPTIONS) and are
      # silently inert under `security`.
      it 'sets the remaining hardened options at the TOP level' do
        opts = saml_options

        expect(opts[:name_identifier_format]).to eq('urn:oasis:names:tc:SAML:2.0:nameid-format:persistent')
        expect(opts[:allowed_clock_drift]).to eq(60)
        expect(opts[:check_duplicated_attributes]).to be true
        expect(opts[:slo_enabled]).to be false
        expect(opts[:security]).not_to have_key(:allowed_clock_drift)
        expect(opts[:security]).not_to have_key(:check_duplicated_attributes)
      end

      it 'forwards only options ruby-saml actually reads' do
        require 'onelogin/ruby-saml'

        expect(OneLogin::RubySaml::Response::AVAILABLE_OPTIONS)
          .to include(:allowed_clock_drift, :check_duplicated_attributes)
      end

      # Fingerprint-only config trusts the certificate EMBEDDED IN THE
      # RESPONSE. No option source may set one. idp_cert_fingerprint_algorithm
      # is NOT a fingerprint (see the next example) and is the one
      # fingerprint-named key allowed through.
      it 'never sets an IdP certificate fingerprint, and sets no skip_* escape hatch' do
        [saml_options, saml[:placeholder_options]].each do |opts|
          expect(opts.keys.map(&:to_s).grep(/fingerprint|\Askip_/)).to eq(['idp_cert_fingerprint_algorithm'])
          expect(opts).not_to have_key(:idp_cert_fingerprint)
          expect(opts).not_to have_key(:idp_cert_multi)
        end
      end

      # ruby-saml matches a certificate embedded in the response against the
      # pinned idp_cert by fingerprint (settings.rb:280 defaults to SHA1) and
      # then verifies with the EMBEDDED one, so the match digest is part of
      # the trust anchor. RE-VERIFY on a ruby-saml bump.
      it 'matches an embedded certificate against the pinned one with SHA-256, not SHA-1' do
        require 'onelogin/ruby-saml'

        [saml_options, saml[:placeholder_options]].each do |opts|
          expect(opts[:idp_cert_fingerprint_algorithm]).to eq(XMLSecurity::Document::SHA256)
        end
        expect(OneLogin::RubySaml::Settings::DEFAULTS[:idp_cert_fingerprint_algorithm]).to eq(XMLSecurity::Document::SHA1)
      end

      it 'passes the IdP trio through, the EntityID byte-for-byte' do
        opts = saml_options

        expect(opts[:idp_sso_service_url]).to eq('https://idp.example.com/saml/sso')
        expect(opts[:idp_entity_id]).to eq('https://idp.example.com/saml/metadata')
        expect(OpenSSL::X509::Certificate.new(opts[:idp_cert]).to_der).to eq(idp.cert.to_der)
      end

      it 'un-escapes a backslash-n encoded certificate' do
        opts = saml_options(SAML_IDP_CERT: idp.cert_pem.gsub("\n", '\n'))

        expect(opts[:idp_cert]).to eq(idp.cert_pem)
      end

      it 'sets uid_attribute only when SAML_UID_ATTRIBUTE is non-blank' do
        expect(saml_options).not_to have_key(:uid_attribute)
        expect(saml_options(SAML_UID_ATTRIBUTE: '  ')).not_to have_key(:uid_attribute)
        expect(saml_options(SAML_UID_ATTRIBUTE: 'employee_id')[:uid_attribute]).to eq('employee_id')
      end

      describe 'sp_entity_id (never blank: ruby-saml skips audience validation on a blank one)' do
        it 'uses SAML_SP_ENTITY_ID when set' do
          expect(saml_options[:sp_entity_id]).to eq('https://ots.example.com/auth/sso/saml/metadata')
        end

        it 'defaults to the public site URL + request path + /metadata' do
          allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => 'secrets.example.com', 'ssl' => true } })

          expect(saml_options(SAML_SP_ENTITY_ID: nil)[:sp_entity_id])
            .to eq('https://secrets.example.com/auth/sso/saml/metadata')
        end

        it 'follows SAML_ROUTE_NAME in the default' do
          allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => 'secrets.example.com' } })

          expect(saml_options(SAML_SP_ENTITY_ID: nil, SAML_ROUTE_NAME: 'okta')[:sp_entity_id])
            .to eq('https://secrets.example.com/auth/sso/okta/metadata')
        end

        it 'refuses, and is not valid, when neither source yields a value' do
          allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => '' } })

          expect { saml_options(SAML_SP_ENTITY_ID: nil) }.to raise_error(ArgumentError, /SAML_SP_ENTITY_ID/)
          expect(saml_valid?(SAML_SP_ENTITY_ID: nil)).to be false
        end
      end

      # The platform IdP registered ONE ACS. Before this was pinned,
      # omniauth-saml defaulted it to the public host of the CURRENT request,
      # so a platform-fallback sign-in on a custom domain advertised an ACS
      # the IdP had never been given.
      describe 'assertion_consumer_service_url (pinned to the platform base, never request-derived)' do
        before do
          allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => 'secrets.example.com', 'ssl' => true } })
        end

        it 'is the platform base URL + callback path' do
          expect(saml_options[:assertion_consumer_service_url]).to eq('https://secrets.example.com/auth/sso/saml/callback')
          expect(Onetime::SsoProvider::Saml.platform_base_url).to eq('https://secrets.example.com')
        end

        it 'follows SAML_ROUTE_NAME' do
          expect(saml_options(SAML_ROUTE_NAME: 'okta')[:assertion_consumer_service_url])
            .to eq('https://secrets.example.com/auth/sso/okta/callback')
        end

        it 'follows site.ssl' do
          allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => 'localhost:7143', 'ssl' => false } })

          expect(saml_options[:assertion_consumer_service_url]).to eq('http://localhost:7143/auth/sso/saml/callback')
        end

        # A URN EntityID has no host to derive anything from; the ACS must
        # not be string-surgery on it.
        it 'derives from site.host even when SAML_SP_ENTITY_ID is an explicit URN' do
          opts = saml_options(SAML_SP_ENTITY_ID: 'urn:example:ots-sp')

          expect(opts[:sp_entity_id]).to eq('urn:example:ots-sp')
          expect(opts[:assertion_consumer_service_url]).to eq('https://secrets.example.com/auth/sso/saml/callback')
        end

        it 'refuses, and is not valid, when site.host is unset even with an explicit SP EntityID' do
          allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => ' ' } })

          expect { saml_options(SAML_SP_ENTITY_ID: 'urn:example:ots-sp') }.to raise_error(ArgumentError, /site\.host/)
          expect(saml_valid?(SAML_SP_ENTITY_ID: 'urn:example:ots-sp')).to be false
        end
      end

      # The HTTP-POST callback is cross-site. Under any cookie but
      # SameSite=None + Secure the pending request id is never presented,
      # so the provider is skipped at boot and not advertised, exactly like
      # a bad trio — never registered as a button that always fails.
      describe 'the session cookie (Saml.session_cookie_problem, checked first)' do
        it 'refuses, and is not valid, under the shipped lax cookie' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)

          expect { saml_options }.to raise_error(ArgumentError, /same_site is 'lax'.*saml_no_pending_request/)
          expect(saml_valid?).to be false
        end

        it 'refuses SameSite=None without Secure' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'none', 'secure' => false)

          expect { saml_options }.to raise_error(ArgumentError, /secure is false/)
          expect(saml_valid?).to be false
        end

        # An install-level prerequisite no SAML_* value can satisfy: the
        # operator must fix it before any trio problem is worth reporting.
        it 'names the cookie before any trio problem' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => false)

          expect { saml_options(SAML_IDP_CERT: 'garbage') }
            .to raise_error(ArgumentError) { |ex| expect(ex.message).to include('same_site').and(satisfy { |m| !m.include?('IdP certificate') }) }
        end
      end

      # The serializers' platform-fallback arms drop this provider on a
      # custom host (its ACS is pinned to site.host).
      describe '.canonical_host_only_route?' do
        it 'is true for the SAML route, following SAML_ROUTE_NAME' do
          expect(saml[:canonical_host_only]).to be true
          ClimateControl.modify(SAML_ROUTE_NAME: nil) do
            expect(described_class.canonical_host_only_route?('saml')).to be true
            expect(described_class.canonical_host_only_route?('okta')).to be false
          end
          ClimateControl.modify(SAML_ROUTE_NAME: 'okta') do
            expect(described_class.canonical_host_only_route?('okta')).to be true
            expect(described_class.canonical_host_only_route?('saml')).to be false
          end
        end

        it 'is false for every other definition, and for a blank or unknown route' do
          expect(definitions.reject { |defn| defn[:key] == :saml }.map { |defn| defn[:canonical_host_only] }).to all(be_nil)
          expect(described_class.canonical_host_only_route?('oidc')).to be false
          expect(described_class.canonical_host_only_route?('')).to be false
          expect(described_class.canonical_host_only_route?(nil)).to be false
          expect(described_class.canonical_host_only_route?('nope')).to be false
        end
      end

      # Blank trust anchors, so RequestBoundSAML refuses (:saml_misconfigured)
      # unless the tenant hook injected a real trio + SP identifiers.
      it 'registers placeholders that fail closed without tenant injection' do
        placeholder = saml[:placeholder_options]

        expect(placeholder[:idp_entity_id]).to eq('')
        expect(placeholder[:sp_entity_id]).to eq('')
        expect(placeholder[:idp_cert]).to eq('')
        expect(URI.parse(placeholder[:idp_sso_service_url]).host).to end_with('.invalid')
        expect(placeholder[:security]).to eq(Onetime::SsoProvider::Saml::SECURITY)
        expect(placeholder.except(:idp_sso_service_url, :idp_entity_id, :idp_cert, :sp_entity_id, :security))
          .to eq(Onetime::SsoProvider::Saml.hardened_options.except(:security))
      end

      # configure_provider rescues the raise and registers no route;
      # :vars_valid is what keeps the login button from being advertised. The
      # two must agree on every case.
      describe 'strategy_options raise / :vars_valid agreement' do
        invalid = {
          'an http SSO service URL' => { SAML_IDP_SSO_SERVICE_URL: 'http://idp.example.com/saml/sso' },
          'a schemeless SSO service URL' => { SAML_IDP_SSO_SERVICE_URL: 'idp.example.com/saml/sso' },
          'a hostless SSO service URL' => { SAML_IDP_SSO_SERVICE_URL: 'https:///saml/sso' },
          'an SSO service URL with credentials' => { SAML_IDP_SSO_SERVICE_URL: 'https://u:p@idp.example.com/sso' },
          'an unparseable SSO service URL' => { SAML_IDP_SSO_SERVICE_URL: 'https://idp example.com/sso' },
          # origin_from_url would strip the dot, admitting an origin the
          # browser never POSTs from (Saml.sso_url_problem).
          'an SSO service URL whose host ends with a dot' => { SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com./sso' },
          # ruby-saml concatenates "?SAMLRequest=" onto the URL; a fragment
          # swallows the query and the IdP receives no request.
          'an SSO service URL with a fragment' => { SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com/sso#login' },
          # URI.parse keeps the ';' on the host; origin_from_url derives no
          # origin, so the CSP / HttpOrigin allowances would omit the IdP
          # while the button was advertised (Saml.sso_url_problem).
          'an SSO service URL with a semicolon in the host' => { SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com;/sso' },
          'a whitespace-only EntityID' => { SAML_IDP_ENTITY_ID: '   ' },
          'an EntityID with trailing whitespace' => { SAML_IDP_ENTITY_ID: 'https://idp.example.com/saml/metadata ' },
          'an EntityID with a control character' => { SAML_IDP_ENTITY_ID: "https://idp.example.com/\nmetadata" },
          'a certificate that is not PEM' => { SAML_IDP_CERT: 'not a certificate' },
          'a PEM block that does not parse' => {
            SAML_IDP_CERT: "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n",
          },
          'a SHA1 fingerprint in place of a certificate' => {
            SAML_IDP_CERT: 'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01',
          },
          # ruby-saml's Utils.is_cert_active drops a not-yet-valid certificate
          # from the trust set exactly as it drops an expired one.
          'a certificate that is not yet valid' => {
            SAML_IDP_CERT: SamlSpec::TestIdp.new(cert_not_before: Time.now + 3600).cert_pem,
          },
        }

        invalid.each do |label, overrides|
          it "refuses #{label}" do
            expect { saml_options(overrides) }.to raise_error(ArgumentError, /SAML_IDP_/)
            expect(saml_valid?(overrides)).to be false
          end
        end

        it 'refuses bare base64 DER without PEM armour' do
          bare = idp.cert_pem.lines.reject { |line| line.start_with?('-----') }.join

          expect { saml_options(SAML_IDP_CERT: bare) }.to raise_error(ArgumentError, /PEM X\.509/)
          expect(saml_valid?(SAML_IDP_CERT: bare)).to be false
        end

        # ruby-saml's format_cert would parse only the FIRST block.
        it 'refuses more than one certificate' do
          two = idp.cert_pem + SamlSpec::TestIdp.new.cert_pem

          expect { saml_options(SAML_IDP_CERT: two) }.to raise_error(ArgumentError, /exactly one/)
          expect(saml_valid?(SAML_IDP_CERT: two)).to be false
        end

        # check_idp_cert_expiration would refuse every login with it anyway.
        it 'refuses an expired certificate, naming the date' do
          expired = SamlSpec::TestIdp.new(cert_not_after: Time.utc(2020, 1, 2)).cert_pem

          expect { saml_options(SAML_IDP_CERT: expired) }.to raise_error(ArgumentError, /expired on 2020-01-02/)
          expect(saml_valid?(SAML_IDP_CERT: expired)).to be false
        end

        # ruby-saml settings.rb:221 filters the IdP certificate through
        # Utils.is_cert_active (not_before <= now && not_after >= now), so a
        # certificate whose window has not opened is dropped from the trust
        # set and every sign-in fails — a config API that accepted it would
        # save a record that can never log anyone in.
        it 'refuses a not-yet-valid certificate, naming when it becomes valid' do
          not_before = Time.utc(2099, 6, 1, 12, 0, 0)
          future     = SamlSpec::TestIdp.new(cert_not_before: not_before, cert_not_after: not_before + 86_400).cert_pem

          expect { saml_options(SAML_IDP_CERT: future) }
            .to raise_error(ArgumentError, /is not valid until 2099-06-01T12:00:00Z/)
          expect(saml_valid?(SAML_IDP_CERT: future)).to be false
        end

        # allow_expired: exists for the tenant RECORD's validity check only
        # (an expired certificate must not make a stored config uneditable).
        # It relaxes the WHOLE validity window — expiry and not-yet-valid —
        # and nothing else, and the builder never uses it.
        describe '.cert_problem(allow_expired: true)' do
          let(:expired) { SamlSpec::TestIdp.new(cert_not_after: Time.utc(2020, 1, 2)).cert_pem }
          let(:future) do
            SamlSpec::TestIdp.new(cert_not_before: Time.utc(2099, 1, 1), cert_not_after: Time.utc(2099, 1, 2)).cert_pem
          end

          it 'accepts an expired certificate that is otherwise well-formed' do
            expect(Onetime::SsoProvider::Saml.cert_problem(expired, allow_expired: true)).to be_nil
            expect(Onetime::SsoProvider::Saml.cert_problem(expired)).to match(/expired on 2020-01-02/)
          end

          it 'accepts a not-yet-valid certificate too (the whole window is skipped)' do
            expect(Onetime::SsoProvider::Saml.cert_problem(future, allow_expired: true)).to be_nil
            expect(Onetime::SsoProvider::Saml.cert_problem(future)).to match(/not valid until 2099-01-01T00:00:00Z/)
          end

          it 'still refuses every structural problem' do
            saml = Onetime::SsoProvider::Saml

            expect(saml.cert_problem('', allow_expired: true)).to match(/blank/)
            expect(saml.cert_problem('AB:CD:EF', allow_expired: true)).to match(/PEM X\.509/)
            expect(saml.cert_problem(expired + expired, allow_expired: true)).to match(/exactly one/)
            expect(saml.cert_problem("-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----", allow_expired: true))
              .to match(/does not parse/)
          end

          it 'is not honoured by the shared builder' do
            expect do
              Onetime::SsoProvider::Saml.strategy_options_for(
                idp_sso_service_url: 'https://idp.example.com/sso', idp_entity_id: 'urn:idp', idp_cert: expired,
              )
            end.to raise_error(ArgumentError, /expired/)
          end
        end

        describe '.parse_cert' do
          it 'returns the certificate for one well-formed PEM block, expired or not' do
            expired = SamlSpec::TestIdp.new(cert_not_after: Time.utc(2020, 1, 2)).cert_pem

            expect(Onetime::SsoProvider::Saml.parse_cert(idp.cert_pem)).to be_a(OpenSSL::X509::Certificate)
            expect(Onetime::SsoProvider::Saml.parse_cert(expired).not_after).to eq(Time.utc(2020, 1, 2))
          end

          it 'returns nil for anything else' do
            ['', nil, 'garbage', idp.cert_pem * 2].each do |value|
              expect(Onetime::SsoProvider::Saml.parse_cert(value)).to be_nil
            end
          end
        end

        # The message reaches the boot log via configure_provider.
        it 'never puts the configured value in the error message' do
          expect { saml_options(SAML_IDP_CERT: 'SENSITIVE-LOOKING-VALUE') }
            .to raise_error(ArgumentError) { |ex| expect(ex.message).not_to include('SENSITIVE-LOOKING-VALUE') }
        end

        it 'is valid, and does not raise, for the good configuration' do
          expect { saml_options }.not_to raise_error
          expect(saml_valid?).to be true
        end

        it 'answers false instead of raising (per-request serializer path)' do
          expect { saml_valid?(SAML_IDP_CERT: 'garbage') }.not_to raise_error
        end
      end

      # The builder the TENANT arm reuses: same hardened hash, no env reads,
      # and no SP identifiers (those are derived per request from full_host).
      describe '.strategy_options_for (shared with the tenant arm)' do
        let(:built) do
          Onetime::SsoProvider::Saml.strategy_options_for(
            idp_sso_service_url: 'https://tenant-idp.example.net/sso',
            idp_entity_id: 'urn:tenant:idp',
            idp_cert: idp.cert_pem,
          )
        end

        it 'returns exactly the trio plus the hardened options' do
          expect(built.keys).to contain_exactly(
            :idp_sso_service_url, :idp_entity_id, :idp_cert,
            *Onetime::SsoProvider::Saml.hardened_options.keys
          )
          expect(built[:security]).to eq(Onetime::SsoProvider::Saml::SECURITY)
        end

        it 'accepts a URN EntityID (an EntityID is a name, not a URL)' do
          expect(built[:idp_entity_id]).to eq('urn:tenant:idp')
        end

        it 'hands out a fresh hash each call, so a caller cannot mutate the shared constant' do
          built[:security][:want_assertions_signed] = false

          expect(Onetime::SsoProvider::Saml::SECURITY[:want_assertions_signed]).to be true
          expect(Onetime::SsoProvider::Saml.hardened_options[:security][:want_assertions_signed]).to be true
        end

        it 'raises without reading the env' do
          ClimateControl.modify(SAML_IDP_ENTITY_ID: 'https://platform-idp.example.com') do
            expect do
              Onetime::SsoProvider::Saml.strategy_options_for(
                idp_sso_service_url: 'https://tenant-idp.example.net/sso', idp_entity_id: '', idp_cert: idp.cert_pem,
              )
            end.to raise_error(ArgumentError, /EntityID is blank/)
          end
        end
      end
    end
  end
end
