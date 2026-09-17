# lib/onetime/sso_provider/saml.rb
#
# frozen_string_literal: true

# SAML 2.0 provider definition (#4450). Field reference and the
# issuer-scoping background live in the registry header
# (lib/onetime/sso_provider/registry.rb). The strategy itself — and every
# SAML-specific gate (InResponseTo binding, issuer equality, transient-NameID
# refusal, assertion replay cache, the scrubbed `extra`) — is
# OmniAuth::Strategies::RequestBoundSAML in ./request_bound_saml.rb. This file
# is configuration only, and stays loadable without omniauth-saml/ruby-saml
# (the registry is read by AuthConfig in processes that never load them).
#
# ISSUER-CAPABLE, BUT NOT THROUGH AN `issuer:` OPTION — and that is the one
# pattern from apple.rb / auth0.rb this file must NEVER copy. In ruby-saml,
# `issuer` is a deprecated alias for OUR OWN SP EntityID (settings.rb:121-122,
# `sp_entity_id = @sp_entity_id || @issuer`). resolve_issuer precedence #1
# reads strategy option :issuer, so declaring one here would key every SAML
# identity on this deployment's EntityID instead of the IdP's — every IdP
# collapses into one issuer namespace, which is the #3838 item-5 takeover
# with extra steps. The SAML issuer reaches resolve_issuer through its own
# branch instead: the strategy's `extra['idp_entity_id']`, which the subclass
# has proven byte-equal to the single Issuer of the validated response (see
# features/omniauth.rb). registry_spec asserts the key's absence.
#
# ONE HARDENED OPTIONS HASH, ONE BUILDER. .strategy_options_for is the single
# source for both surfaces: the platform definition below calls it with the
# env trio, and the tenant arm (CustomDomain::SsoConfig#to_omniauth_options)
# calls it with the record's trio. Do not restate the hash anywhere else.
#
#   - omniauth-saml builds `OneLogin::RubySaml::Settings.new(options)` WITHOUT
#     keep_security_attributes, so a partial `security:` hash REPLACES
#     ruby-saml's defaults and every unset key becomes nil
#     (settings.rb:277-304). SECURITY is therefore always the FULL hash.
#   - ruby-saml's own defaults are weak: want_assertions_signed false, SHA1
#     digest/signature, no cert-expiry check, no strict audience validation.
#   - `allowed_clock_drift` and `check_duplicated_attributes` are Response
#     options (response.rb AVAILABLE_OPTIONS), not Settings accessors. They
#     only work as TOP-LEVEL strategy options, which omniauth-saml forwards
#     (saml.rb:273-282); nested under `security` they are silently inert.
#   - `idp_cert_fingerprint` is never set and never accepted: fingerprint-only
#     config trusts whatever certificate the RESPONSE embeds (SHA1 by
#     default). Trust is a pinned PEM certificate or nothing.
#   - `idp_sso_service_url_runtime_params` is not in this hash on purpose.
#     OmniAuth deep-merges instance options over class defaults, so `{}` here
#     could not clear the gem's RelayState-forwarding default; the subclass
#     clears it as a class-level default instead.
#   - `slo_enabled: false`. The gem's IdP-initiated logout default is
#     session.clear, which bypasses this app's active-session rows; SLO needs
#     its own design against the revoke/destroy vocabulary before it is on.
#
# The digest/signature/NameID-format values are W3C/OASIS URIs written as
# literals so this file needs no gem; registry_spec pins them to the
# XMLSecurity::Document constants. RE-VERIFY on any ruby-saml bump.
#
# MISSING OR INVALID CONFIG SKIPS THE PROVIDER; IT DOES NOT FAIL BOOT. #4450's
# issue text asks for a boot failure. configure_provider is deliberately built
# never to kill boot (features/omniauth.rb: an exception inside Rodauth
# configuration takes password, MFA and magic-link sign-in down with it), so
# SAML follows the Auth0 contract instead: strategy_options raises with a
# message naming the variable, configure_provider logs it and registers no
# route, and :vars_valid keeps the login button from being advertised.
#
# ⚠️  OPERATOR PREREQUISITE — SameSite=None session cookie. The HTTP-POST
# binding delivers the response as a CROSS-SITE POST from the IdP, exactly like
# Sign in with Apple's form_post (see apple.rb for the full account). A
# SameSite=Lax cookie is withheld, the session holding the pending
# AuthnRequest id is absent, and the strategy refuses the response as
# :saml_no_pending_request. SAML therefore requires
# `site.session.same_site: none` with `secure: true`. The other half —
# Rack::Protection::HttpOrigin admitting the IdP's Origin on the callback path
# — is handled in code from :idp_origin_from below
# (Onetime::Middleware::HttpOriginOptions).
#
# THE CSP / HttpOrigin ORIGIN COMES FROM THE SSO SERVICE URL, NOT THE ENTITYID.
# An EntityID is an opaque name — often a URN, often on a different host than
# the login endpoint. The browser is redirected to, and posts back from, the
# SSO service URL's origin.
#
# IdP-INITIATED SSO IS UNSUPPORTED, by design (request_bound_saml.rb).
#
# ACCOUNT VERIFICATION RESTS ON IdP TRUST. SAML has no email_verified claim;
# a JIT account is stamped verified because the operator configured this IdP.
# An attribute the IdP happens to NAME `email_verified` with the value false
# is still honoured as a hold (hooks/omniauth.rb email_verification_hold).

require 'openssl'
require 'uri'

module Onetime
  module SsoProvider
    module Saml
      PERSISTENT_NAME_ID_FORMAT = 'urn:oasis:names:tc:SAML:2.0:nameid-format:persistent'

      # == XMLSecurity::Document::SHA256 / ::RSA_SHA256 (pinned by registry_spec).
      DIGEST_SHA256        = 'http://www.w3.org/2001/04/xmlenc#sha256'
      SIGNATURE_RSA_SHA256 = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'

      # Seconds. Also sizes the replay-cache TTL (request_bound_saml.rb reads
      # the same top-level option).
      ALLOWED_CLOCK_DRIFT = 60

      # The FULL ruby-saml security hash — see the header for why it can never
      # be partial. We sign nothing (no SP key is configured), so every
      # *_signed / embed_sign key is false; what we REQUIRE of the IdP is
      # want_assertions_signed, SHA-256 and an unexpired certificate.
      SECURITY = {
        authn_requests_signed: false,
        logout_requests_signed: false,
        logout_responses_signed: false,
        want_assertions_signed: true,
        want_assertions_encrypted: false,
        want_name_id: true,
        metadata_signed: false,
        embed_sign: false,
        digest_method: DIGEST_SHA256,
        signature_method: SIGNATURE_RSA_SHA256,
        check_idp_cert_expiration: true,
        check_sp_cert_expiration: false,
        strict_audience_validation: true,
        lowercase_url_encoding: false,
      }.freeze

      # Everything about the strategy that is NOT per-IdP. A fresh, unfrozen
      # Hash per call: OmniAuth merges it into a Mash, and callers add keys.
      #
      # @return [Hash]
      def self.hardened_options
        {
          name_identifier_format: PERSISTENT_NAME_ID_FORMAT,
          allowed_clock_drift: ALLOWED_CLOCK_DRIFT,
          check_duplicated_attributes: true,
          slo_enabled: false,
          security: SECURITY.dup,
        }
      end

      # The single builder both surfaces use: hardened options + a VALIDATED
      # IdP trio. Raises rather than returning a half-trusted hash — a SAML
      # strategy with a blank EntityID or an unparseable certificate has no
      # trust anchor, and ruby-saml answers that by skipping the check.
      #
      # Deliberately has no sp_entity_id / assertion_consumer_service_url
      # parameter: those are per-surface (platform: see .platform_options;
      # tenant: derived per request from strategy.full_host).
      #
      # @param idp_sso_service_url [String] https URL of the IdP SSO endpoint
      # @param idp_entity_id [String] the IdP's EntityID — the identity issuer
      # @param idp_cert [String] one PEM X.509 signing certificate
      # @param uid_attribute [String, nil] attribute to use as uid instead of NameID
      # @return [Hash] strategy options (minus name:)
      # @raise [ArgumentError] naming the first invalid field
      def self.strategy_options_for(idp_sso_service_url:, idp_entity_id:, idp_cert:, uid_attribute: nil)
        problem = sso_url_problem(idp_sso_service_url) ||
                  entity_id_problem(idp_entity_id) ||
                  cert_problem(idp_cert)
        raise ArgumentError, problem if problem

        options                       = hardened_options
        options[:idp_sso_service_url] = idp_sso_service_url.to_s.strip
        # NOT stripped, NOT normalized: the subclass requires byte equality
        # with the response Issuer, and this exact string is the issuer half
        # of the (provider, issuer, uid) identity key. entity_id_problem has
        # already refused a value with surrounding whitespace.
        options[:idp_entity_id]       = idp_entity_id.to_s
        options[:idp_cert]            = normalize_pem(idp_cert)

        attribute               = uid_attribute.to_s.strip
        options[:uid_attribute] = attribute unless attribute.empty?
        options
      end

      # https only. Unlike OIDC_ISSUER / AUTH0_DOMAIN there is no http
      # allowance: the signed assertion travels through the user's browser
      # from this origin, and an http origin lets a network attacker replace
      # the login page that collects the IdP credentials.
      #
      # @return [String, nil] problem description, or nil when usable
      def self.sso_url_problem(url)
        str = url.to_s.strip
        return 'IdP SSO service URL is blank' if str.empty?

        uri = URI.parse(str)
        return 'IdP SSO service URL must be an https:// URL' unless uri.is_a?(URI::HTTPS)
        return 'IdP SSO service URL has no host' if uri.host.to_s.strip.empty?
        return 'IdP SSO service URL must not carry credentials' if uri.userinfo

        nil
      rescue URI::Error
        'IdP SSO service URL is not a valid URL'
      end

      # @return [String, nil] problem description, or nil when usable
      def self.entity_id_problem(entity_id)
        str = entity_id.to_s
        return 'IdP EntityID is blank' if str.strip.empty?
        return 'IdP EntityID has leading or trailing whitespace' unless str == str.strip
        return 'IdP EntityID contains control characters' if str.match?(/[\x00-\x1f\x7f]/)

        nil
      end

      # Exactly one PEM CERTIFICATE block that OpenSSL parses and that has not
      # expired. PEM is required (not bare base64, not DER): ruby-saml's
      # format_cert would accept the former and quietly parse only the FIRST
      # of several blocks, and "which certificate is trusted" must not depend
      # on that. An expired certificate is refused here because
      # check_idp_cert_expiration would refuse every login with it anyway —
      # better a skipped provider and a named variable than a button that
      # always fails.
      #
      # allow_expired: exists for ONE caller — the tenant record's own
      # validity check (CustomDomain::SsoConfig#validation_errors). A stored
      # record whose certificate has since expired must stay EDITABLE (a
      # PATCH that disables SSO re-validates the whole record), so expiry is
      # not a model invariant there. It is still refused everywhere a
      # certificate is ACCEPTED or USED: the API write path, test_connection,
      # and .strategy_options_for — all of which leave this false.
      #
      # @param pem [String, nil]
      # @param allow_expired [Boolean] structure-only check (see above)
      # @return [String, nil] problem description, or nil when usable
      def self.cert_problem(pem, allow_expired: false)
        cert = parse_single_cert(pem)
        return cert if cert.is_a?(String)
        return nil if allow_expired
        return "IdP certificate expired on #{cert.not_after.utc.strftime('%Y-%m-%d')}" if cert.not_after < Time.now

        nil
      end

      # The parsed certificate, or nil when it is not exactly one parseable
      # PEM block. For callers that REPORT on a certificate (test_connection's
      # expiry date) — never a substitute for .cert_problem.
      #
      # @return [OpenSSL::X509::Certificate, nil]
      def self.parse_cert(pem)
        cert = parse_single_cert(pem)
        cert.is_a?(String) ? nil : cert
      end

      # @return [OpenSSL::X509::Certificate, String] the certificate, or the
      #   structural problem as a String
      def self.parse_single_cert(pem)
        text = normalize_pem(pem).to_s
        return 'IdP certificate is blank' if text.strip.empty?

        blocks = text.scan('-----BEGIN CERTIFICATE-----').length
        return 'IdP certificate must be a PEM X.509 certificate (-----BEGIN CERTIFICATE-----)' if blocks.zero?
        return 'IdP certificate must contain exactly one PEM certificate' if blocks > 1

        OpenSSL::X509::Certificate.new(text)
      rescue OpenSSL::X509::CertificateError
        'IdP certificate does not parse as X.509'
      end
      private_class_method :parse_single_cert

      # Same convention as APPLE_PRIVATE_KEY (apple.rb): deployments carry
      # multi-line values as one line with literal \n. A value that already
      # contains newlines passes through untouched.
      #
      # @param pem [String, nil]
      # @return [String, nil]
      def self.normalize_pem(pem)
        return pem if pem.nil?

        text = pem.to_s
        text.include?('\n') ? text.gsub('\n', "\n") : text
      end

      # Our SP EntityID on the PLATFORM surface: SAML_SP_ENTITY_ID when set,
      # otherwise the public site URL + the strategy's request path +
      # '/metadata' — the URL the SP metadata is actually served from, which
      # is the convention IdP admins expect. NEVER blank: ruby-saml skips
      # audience validation on a blank sp_entity_id (response.rb
      # validate_audience), and the subclass refuses one outright.
      #
      # A boot-time constant, not derived per request: the IdP registers ONE
      # audience for the platform, whichever host a request arrives on.
      #
      # @param route_name [String] the configured route name (SAML_ROUTE_NAME)
      # @return [String]
      # @raise [ArgumentError] when neither source yields a value
      def self.platform_sp_entity_id(route_name)
        explicit = ENV.fetch('SAML_SP_ENTITY_ID', '').to_s.strip
        return explicit unless explicit.empty?

        conf = defined?(OT) && OT.respond_to?(:conf) ? OT.conf : nil
        host = conf&.dig('site', 'host').to_s.strip
        if host.empty?
          raise ArgumentError,
            'SAML_SP_ENTITY_ID is unset and site.host is not configured, so no SP EntityID can be derived'
        end

        scheme = conf.dig('site', 'ssl') == false ? 'http' : 'https'
        "#{scheme}://#{host}/auth/sso/#{route_name}/metadata"
      end

      # Platform strategy options from the env. Raises ArgumentError (caught by
      # configure_provider, mirrored by .platform_usable?) with a message that
      # names the offending variable.
      #
      # @return [Hash]
      def self.platform_options
        options = begin
          strategy_options_for(
            idp_sso_service_url: ENV.fetch('SAML_IDP_SSO_SERVICE_URL', nil),
            idp_entity_id: ENV.fetch('SAML_IDP_ENTITY_ID', nil),
            idp_cert: ENV.fetch('SAML_IDP_CERT', nil),
            uid_attribute: ENV.fetch('SAML_UID_ATTRIBUTE', nil),
          )
        rescue ArgumentError => ex
          raise ArgumentError,
            "#{ex.message} (check SAML_IDP_SSO_SERVICE_URL, SAML_IDP_ENTITY_ID, SAML_IDP_CERT)"
        end

        options[:sp_entity_id] = platform_sp_entity_id(ENV.fetch('SAML_ROUTE_NAME', 'saml'))
        options
      end

      # Are the SAML_* vars not just SET but USABLE? The :vars_valid predicate
      # (see auth0.rb domain_usable? for why the advertised and registered
      # provider sets need one shared answer). Runs per request on the
      # serializer and HttpOrigin paths; one X.509 parse, no I/O.
      #
      # @return [Boolean]
      def self.platform_usable?
        platform_options
        true
      rescue ArgumentError
        false
      end

      DEFINITION = {
        key: :saml,
        label: 'SAML',
        strategy: :request_bound_saml,
        # Requires omniauth-saml itself, re-points ruby-saml's STDOUT logger,
        # and registers the :request_bound_saml camelization. lib/ is on the
        # load path.
        gem_require: 'onetime/sso_provider/request_bound_saml',
        issuer_capable: true,
        # SAML has no client credential: there is deliberately no
        # SAML_CLIENT_ID, and configure_provider logs 'client_id: (none)'.
        required_vars: %w[SAML_IDP_SSO_SERVICE_URL SAML_IDP_ENTITY_ID SAML_IDP_CERT],
        vars_valid: -> { platform_usable? },
        route_var: 'SAML_ROUTE_NAME',
        route_default: 'saml',
        display_var: 'SAML_DISPLAY_NAME',
        display_default: 'SAML SSO',
        trust_var: 'SAML_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin_from: 'SAML_IDP_SSO_SERVICE_URL',
        # Registered when org-level SSO is on and the platform has no SAML
        # config, so the route exists for the OmniAuthTenant hook to inject a
        # tenant's trio + per-request SP identifiers into. The trust anchors
        # are BLANK on purpose, not 'placeholder': RequestBoundSAML refuses a
        # blank idp_entity_id / sp_entity_id at both phases
        # (:saml_misconfigured), so a request that reaches this route without
        # tenant injection fails closed instead of redirecting somewhere. No
        # :issuer key here either.
        placeholder_options: hardened_options.merge(
          security: SECURITY,
          idp_sso_service_url: 'https://placeholder.invalid/saml/sso',
          idp_entity_id: '',
          idp_cert: '',
          sp_entity_id: '',
        ).freeze,
        strategy_options: -> { platform_options },
      }.freeze
    end
  end
end
