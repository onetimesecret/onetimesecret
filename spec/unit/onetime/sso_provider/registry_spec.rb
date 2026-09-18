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
        AUTH0_CLIENT_ID: 'cid',
        AUTH0_CLIENT_SECRET: 'cs',
        AUTH0_DOMAIN: 'https://tenant.us.auth0.com',
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

    # The Auth0 identity key is ('auth0', <this string>, sub), and it is also
    # the value JWTValidator#verify_iss would compare against if the gem's
    # scope gate were ever repaired (see lib/onetime/sso_provider/auth0.rb).
    # Auth0 asserts `iss` WITH a trailing slash, so a slashless value here
    # would key every row on a string the IdP never sends.
    it 'pins the Auth0 issuer to the domain with exactly one trailing slash' do
      ClimateControl.modify(AUTH0_DOMAIN: 'https://tenant.us.auth0.com') do
        opts = described_class.fetch(:auth0)[:strategy_options].call
        expect(opts[:issuer]).to eq('https://tenant.us.auth0.com/')
      end
    end

    it 'does not double the Auth0 trailing slash when the domain already has one' do
      ClimateControl.modify(AUTH0_DOMAIN: 'https://tenant.us.auth0.com/') do
        opts = described_class.fetch(:auth0)[:strategy_options].call
        expect(opts[:issuer]).to eq('https://tenant.us.auth0.com/')
      end
    end

    # A bare hostname is what Auth0's own documentation shows, so operators
    # will reach for it. The strategy would accept it and the CSP form-action
    # origin would silently be omitted (AuthConfig#origin_from_url needs a
    # scheme), producing an SSO route that only fails in a real browser.
    # Fail at boot, where the message can name the variable.
    it 'refuses a schemeless AUTH0_DOMAIN rather than breaking CSP silently' do
      ClimateControl.modify(AUTH0_DOMAIN: 'tenant.us.auth0.com') do
        expect { described_class.fetch(:auth0)[:strategy_options].call }
          .to raise_error(ArgumentError, /AUTH0_DOMAIN must be a full URL/)
      end
    end

    it 'accepts an http AUTH0_DOMAIN (private/self-hosted Auth0 deployments)' do
      ClimateControl.modify(AUTH0_DOMAIN: 'http://auth0.internal:3000') do
        opts = described_class.fetch(:auth0)[:strategy_options].call
        expect(opts[:issuer]).to eq('http://auth0.internal:3000/')
      end
    end

    # The companion to that raise. required_vars sees AUTH0_DOMAIN as PRESENT
    # and would advertise a login button, while configure_provider rescues the
    # raise and registers no route — a button leading nowhere. :vars_valid is
    # the predicate AuthConfig#provider_active? consults so the advertised set
    # and the registered set cannot disagree.
    describe 'the Auth0 :vars_valid predicate' do
      it 'is false for a schemeless AUTH0_DOMAIN' do
        ClimateControl.modify(AUTH0_DOMAIN: 'tenant.us.auth0.com') do
          expect(described_class.fetch(:auth0)[:vars_valid].call).to be false
        end
      end

      it 'is true for a scheme-ful AUTH0_DOMAIN' do
        ClimateControl.modify(AUTH0_DOMAIN: 'https://tenant.us.auth0.com') do
          expect(described_class.fetch(:auth0)[:vars_valid].call).to be true
        end
      end

      # It swallows the ArgumentError rather than propagating it: this runs on
      # the per-request serializer path, not only at boot.
      it 'answers false instead of raising' do
        ClimateControl.modify(AUTH0_DOMAIN: 'tenant.us.auth0.com') do
          expect { described_class.fetch(:auth0)[:vars_valid].call }.not_to raise_error
        end
      end

      # Every other definition is presence-only; the field is opt-in, and a
      # definition without it must be treated as always valid. Exactly the
      # definitions whose strategy_options can RAISE carry one (SAML: see the
      # SAML block below).
      it 'is one of only two in the registry' do
        with_predicate = described_class::DEFINITIONS.select { |defn| defn[:vars_valid] }
        expect(with_predicate.map { |defn| defn[:key] }).to eq([:auth0, :saml])
      end
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
      # `issuer:` key, the pattern Apple and Auth0 legitimately use, would key
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

        # allow_expired: exists for the tenant RECORD's validity check only
        # (an expired certificate must not make a stored config uneditable).
        # It relaxes expiry and nothing else, and the builder never uses it.
        describe '.cert_problem(allow_expired: true)' do
          let(:expired) { SamlSpec::TestIdp.new(cert_not_after: Time.utc(2020, 1, 2)).cert_pem }

          it 'accepts an expired certificate that is otherwise well-formed' do
            expect(Onetime::SsoProvider::Saml.cert_problem(expired, allow_expired: true)).to be_nil
            expect(Onetime::SsoProvider::Saml.cert_problem(expired)).to match(/expired on 2020-01-02/)
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
