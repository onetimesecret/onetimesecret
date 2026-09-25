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
# pattern from apple.rb this file must NEVER copy. In ruby-saml,
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
#     default). Trust is a pinned PEM certificate or nothing. That
#     certificate is ONE PEM CERTIFICATE block and nothing else (no key, no
#     bundle, no surrounding text): the stored value is served back as
#     public data by the SSO config API, so .cert_problem refuses anything
#     that is not exactly the block.
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
# SAML is skipped instead: strategy_options raises with a message naming the
# variable, configure_provider rescues it, logs one error line and registers
# no platform route, and :vars_valid keeps the login button from being
# advertised.
#
# ⚠️  OPERATOR PREREQUISITE — SameSite=None session cookie. The HTTP-POST
# binding delivers the response as a CROSS-SITE POST from the IdP, exactly like
# Sign in with Apple's form_post (see apple.rb for the full account). A
# SameSite=Lax cookie is withheld, the session holding the pending
# AuthnRequest id is absent, and the strategy refuses the response as
# :saml_no_pending_request. SAML therefore requires
# `site.session.same_site: none` with `secure: true`. .session_cookie_problem
# is that rule as code, and it has three consumers. On the PLATFORM surface
# it is the first check in .platform_options, so an incompatible cookie is
# handled like a missing variable (above): configure_provider logs the
# problem (error level, boot does not abort), registers no platform route,
# and :vars_valid keeps the button off the login page, rather than
# advertising a provider that can never complete a sign-in. The tenant
# PLACEHOLDER registration (ORGS_SSO_ENABLED with no platform vars) logs the
# same problem, because the placeholder still registers, and the tenant API
# refuses to save a saml config under one (SamlFields). The other half —
# Rack::Protection::HttpOrigin admitting the IdP's Origin on the callback
# path — is handled in code from :idp_origin_from below
# (Onetime::Middleware::HttpOriginOptions).
#
# PLATFORM SAML BOOTS WITH CANONICAL IDENTIFIERS. The platform IdP registers
# one SP EntityID and may register ACS URLs for verified custom domains.
# .platform_options always pins the canonical ACS as the safe default. During
# an explicitly allowed platform fallback, OmniAuthTenant may replace ONLY the
# ACS with strategy.full_host + callback_path after Auth::PublicHost.resolve
# proves the request host is an existing verified custom domain. The platform
# SP EntityID and IdP trust anchors remain unchanged. Unknown, unverified, and
# datastore-indeterminate hosts retain no fallback path and fail closed. Native
# tenant SAML still derives both SP identifiers from the tenant request host.
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
require 'time'
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

      # Separator inside a TENANT SAML issuer key (see .tenant_issuer). A
      # CustomDomain identifier is a base-36 Familia id, so it can never
      # contain this character and the key splits unambiguously.
      TENANT_ISSUER_SEPARATOR = '|'

      # The FULL ruby-saml security hash — see the header for why it can never
      # be partial. We sign nothing (no SP key is configured), so every
      # *_signed / embed_sign key is false; what we REQUIRE of the IdP is
      # want_assertions_signed and an unexpired certificate.
      #
      # digest_method / signature_method are SP-SIDE signing parameters only
      # (ruby-saml xml_security.rb:147 `sign_document`), which with no SP key
      # never runs; they are set to SHA-256 so nothing SHA1 is ever advertised
      # in SP metadata. They do NOT constrain the IdP: the verifier reads the
      # SignatureMethod and DigestMethod the RESPONSE declares
      # (xml_security.rb:341, :415) and maps any URI it does not recognise to
      # SHA1, so a SHA1-signed response verifies under this hash. The
      # minimum-algorithm gate is therefore a RequestBoundSAML check
      # (signature_algorithm_refusal: an allowlist of SHA-256/384/512 RSA
      # methods and SHA-256/384/512 digests, refusal
      # :saml_weak_signature_algorithm), not a value here. RE-VERIFY on a
      # ruby-saml bump. (#4450)
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

      # The issuer half of a TENANT SAML identity key: the validated EntityID
      # scoped to the custom domain whose record vouched for it.
      #
      # WHY THE DOMAIN IS PART OF THE KEY. For OIDC / Entra tenants the issuer
      # string is bound to an origin the server verified — discovery and the
      # JWKS fetch tie `iss` to a TLS host — so two tenants naming the same
      # issuer are, provably, the same IdP and may share identity rows. A SAML
      # EntityID is an opaque, UNAUTHENTICATED name: a tenant admin asserts it
      # alongside their OWN signing certificate, and nothing outside that
      # record vouches for the pair. Keyed on the bare EntityID, tenant B could
      # configure tenant A's EntityID (or the platform's SAML_IDP_ENTITY_ID)
      # with B's certificate, have B's IdP sign a response naming it and any
      # NameID it likes, pass every strategy gate (signature verifies against
      # B's pinned certificate, Issuer equals B's configured value) and resolve
      # A's victim row — a cross-tenant account takeover that then joins the
      # victim into B's organization. Scoping the key to the domain makes the
      # trust anchor and the identity namespace the same thing: the record
      # that pinned the certificate is the record whose identities it can
      # match. The platform surface keeps the bare EntityID (its trust anchor
      # is the env, one per deployment), so a tenant's rows can never match a
      # platform row in either direction.
      #
      # Written by resolve_issuer (features/omniauth.rb) at callback time —
      # the only writer. The EntityID is NOT stripped or normalized here for
      # the same reason strategy_options_for does not.
      #
      # @param domain_id [String] the CustomDomain identifier (`domainid`)
      # @param idp_entity_id [String] the validated IdP EntityID
      # @return [String] "<domain_id>|<idp_entity_id>"
      # @raise [ArgumentError] when either half is blank
      def self.tenant_issuer(domain_id, idp_entity_id)
        raise ArgumentError, 'tenant SAML issuer needs a domain id' if domain_id.to_s.strip.empty?
        raise ArgumentError, 'tenant SAML issuer needs an IdP EntityID' if idp_entity_id.to_s.strip.empty?

        "#{domain_id}#{TENANT_ISSUER_SEPARATOR}#{idp_entity_id}"
      end

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
          # NOT a fingerprint (idp_cert_fingerprint is never set): the digest
          # ruby-saml uses to match a certificate EMBEDDED in the response
          # against the pinned idp_cert before verifying with the embedded
          # one (xml_security.rb validate_document; settings.rb:280 defaults
          # it to SHA1). A chosen-prefix SHA-1 collision on the DER would let
          # an attacker's certificate pass as the pinned one; SHA-256 closes
          # that. Absent an embedded certificate the pinned one is used
          # directly and this is inert. RE-VERIFY on a ruby-saml bump.
          idp_cert_fingerprint_algorithm: DIGEST_SHA256,
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
      # @param idp_cert [String] one PEM X.509 signing certificate and nothing
      #   else (the stored value is public data — see .cert_problem)
      # @param uid_attribute [String, nil] attribute to use as uid instead of NameID
      # @return [Hash] strategy options (minus name:)
      # @raise [ArgumentError] naming the first invalid field
      NAME_ID_FORMATS = [
        PERSISTENT_NAME_ID_FORMAT,
        'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
        'urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified',
        'urn:oasis:names:tc:SAML:2.0:nameid-format:transient',
        'omit',
      ].freeze

      def self.name_id_format_problem(value)
        return nil if NAME_ID_FORMATS.include?(value)

        'NameID policy must be a supported NameID format URI or omit'
      end

      def self.callback_origins_problem(value)
        return 'Callback origins must be an array of at most 16 HTTPS origins' unless value.is_a?(Array) && value.size <= 16

        return nil if value.all? { |origin| origin.is_a?(String) && sso_url_problem(origin).nil? && csp_origin_for(origin) == origin }

        'Callback origins must be exact HTTPS origins without paths, wildcards, credentials, or null'
      end

      def self.strategy_options_for(idp_sso_service_url:, idp_entity_id:, idp_cert:, uid_attribute: nil, name_id_format: PERSISTENT_NAME_ID_FORMAT)
        problem = sso_url_problem(idp_sso_service_url) ||
                  entity_id_problem(idp_entity_id) ||
                  cert_problem(idp_cert) || name_id_format_problem(name_id_format)
        raise ArgumentError, problem if problem

        options                          = hardened_options
        options[:name_identifier_format] = name_id_format == 'omit' ? nil : name_id_format
        options[:idp_sso_service_url]    = idp_sso_service_url.to_s.strip
        # NOT stripped, NOT normalized: the subclass requires byte equality
        # with the response Issuer, and this exact string is the issuer half
        # of the (provider, issuer, uid) identity key. entity_id_problem has
        # already refused a value with surrounding whitespace.
        options[:idp_entity_id]          = idp_entity_id.to_s
        options[:idp_cert]               = normalize_pem(idp_cert)

        attribute               = uid_attribute.to_s.strip
        options[:uid_attribute] = attribute unless attribute.empty?
        options
      end

      # https only. Unlike OIDC_ISSUER there is no http
      # allowance: the signed assertion travels through the user's browser
      # from this origin, and an http origin lets a network attacker replace
      # the login page that collects the IdP credentials.
      #
      # No trailing dot on the host. The URL is admitted into the CSP
      # form-action and HttpOrigin allowances as an ORIGIN derived through
      # AuthConfig.origin_from_url, and otto's normalize_origin strips one
      # trailing dot from the host (otto 2.9.0 request_extras.rb; its own
      # comment notes browsers do NOT equate "idp.example.com." with
      # "idp.example.com"). The browser is redirected to the dotted host and
      # the IdP's HTTP-POST callback then carries Origin
      # "https://idp.example.com." — which HttpOriginOptions compares as a
      # raw string against the stripped admitted origin, so every callback
      # is refused (403) and the CSP directive lists a host the browser never
      # POSTs from. Accepting such a URL produces a record that can never
      # complete a login; refuse it where the URL is accepted instead.
      #
      # No fragment. ruby-saml's Authrequest#create appends "SAMLRequest=..."
      # to idp_sso_service_url by string concatenation, joined with "&" when
      # the URL already carries a query and "?" otherwise (authrequest.rb,
      # params_prefix), so a query string is FINE — Google Workspace's IdP
      # URL is "https://accounts.google.com/o/saml2/idp?idpid=..." and must
      # be accepted. A "#frag" already on the URL is not: it swallows the
      # whole appended query, and the browser is sent to the IdP with no
      # SAMLRequest at all.
      #
      # The host must yield a CSP-safe ORIGIN. URI.parse keeps a trailing ';'
      # (or quote, comma, bracket) on the host, so "https://idp.example.com;/sso"
      # parses — but AuthConfig.origin_from_url, the one funnel the CSP
      # form-action and HttpOrigin allowances derive the IdP origin through,
      # returns nil for such a host and active_provider_origins /
      # tenant_idp_origin drop it silently. The provider would be advertised
      # (platform) or saved (tenant) while no callback could ever be admitted.
      # Checking THROUGH origin_from_url here is what makes this one rule
      # cover the platform env, the model invariant and the API path alike.
      #
      SSO_URL_ORIGIN_PROBLEM = 'IdP SSO service URL must have a plain hostname ' \
                               '(no spaces, quotes or punctuation in the host)'

      # @return [String, nil] problem description, or nil when usable
      def self.sso_url_problem(url)
        str = url.to_s.strip
        return 'IdP SSO service URL is blank' if str.empty?

        uri = URI.parse(str)
        return 'IdP SSO service URL must be an https:// URL' unless uri.is_a?(URI::HTTPS)
        return 'IdP SSO service URL has no host' if uri.host.to_s.strip.empty?
        return 'IdP SSO service URL must not carry credentials' if uri.userinfo
        return 'IdP SSO service URL host must not end with a dot' if uri.host.end_with?('.')
        return 'IdP SSO service URL must not contain a fragment' if uri.fragment
        return SSO_URL_ORIGIN_PROBLEM if csp_origin_for(str).nil?

        nil
      rescue URI::Error
        'IdP SSO service URL is not a valid URL'
      end

      # The origin the CSP / HttpOrigin allowances would derive from the URL,
      # or nil when they would derive none. Resolved lazily: auth_config.rb
      # requires the registry (and so this file), so a top-level require here
      # would be circular.
      #
      # @return [String, nil]
      def self.csp_origin_for(url)
        require_relative '../auth_config' unless defined?(Onetime::AuthConfig)
        Onetime::AuthConfig.origin_from_url(url)
      rescue StandardError
        nil
      end
      private_class_method :csp_origin_for

      # @return [String, nil] problem description, or nil when usable
      def self.entity_id_problem(entity_id)
        str = entity_id.to_s
        return 'IdP EntityID is blank' if str.strip.empty?
        return 'IdP EntityID has leading or trailing whitespace' unless str == str.strip
        return 'IdP EntityID contains control characters' if str.match?(/[\x00-\x1f\x7f]/)

        nil
      end

      # Exactly one PEM CERTIFICATE block, with NOTHING around it, that
      # OpenSSL parses and whose validity window contains NOW. PEM is required
      # (not bare base64, not DER): ruby-saml's format_cert would accept the
      # former and quietly parse only the FIRST of several blocks, and "which
      # certificate is trusted" must not depend on that. Nothing besides the
      # one block is accepted because the value is stored whole and returned
      # as PUBLIC data by the SSO config API (serializers.rb does not mask
      # idp_cert): a pasted bundle that carries the IdP's private key after
      # the certificate would parse, be saved, and be disclosed to every org
      # admin (parse_single_cert). Both ends of the window are checked
      # because ruby-saml checks both: settings.rb:221 filters the IdP
      # certificate through Utils.is_cert_active (not_before <= now AND
      # not_after >= now), so a certificate that has expired OR is not yet
      # valid is silently dropped from the trust set and every login is
      # refused. Better a skipped provider and a named variable than a button
      # that always fails. RE-VERIFY on a ruby-saml bump.
      #
      # allow_expired: exists for ONE caller — the tenant record's own
      # validity check (CustomDomain::SsoConfig#saml_validation_errors). It
      # skips the WHOLE validity-window check (expired AND not yet valid),
      # not only expiry, despite its name: the keyword predates the
      # not_before check and its caller lives in the model, so the name is
      # kept and the contract widened. A stored record whose certificate has
      # since expired must stay EDITABLE (a PATCH that disables SSO
      # re-validates the whole record), so the window is not a model
      # invariant there — and a not-yet-valid certificate could only be
      # stored before this check existed, so it needs the same escape for
      # the same reason. The window is still refused everywhere a
      # certificate is ACCEPTED or USED: the API write path, test_connection,
      # and .strategy_options_for — all of which leave this false.
      #
      # @param pem [String, nil]
      # @param allow_expired [Boolean] structure-only check: skip the whole
      #   validity window (see above)
      # @return [String, nil] problem description, or nil when usable
      def self.cert_problem(pem, allow_expired: false, allow_unsupported_key: false)
        cert = cached_certificate(pem)
        return cert if cert.is_a?(String)
        unless allow_unsupported_key || cert.public_key.is_a?(OpenSSL::PKey::RSA)
          return 'IdP certificate must contain an RSA public key; other public-key types are not supported'
        end
        return nil if allow_expired

        now = Time.now
        return "IdP certificate expired on #{cert.not_after.utc.strftime('%Y-%m-%d')}" if cert.not_after < now
        return "IdP certificate is not valid until #{cert.not_before.utc.iso8601}" if cert.not_before > now

        nil
      end

      # The parsed certificate, or nil when it is not exactly one parseable
      # PEM block. For callers that REPORT on a certificate (test_connection's
      # expiry date) — never a substitute for .cert_problem.
      #
      # @return [OpenSSL::X509::Certificate, nil]
      def self.parse_cert(pem)
        cert = cached_certificate(pem)
        cert.is_a?(String) ? nil : cert.dup
      end

      CERTIFICATE_CACHE_LOCK = Mutex.new
      CERTIFICATE_CACHE      = {}

      # Cache only parsing, never availability. Every caller still checks both
      # ends of the validity window and every other configuration input live.
      def self.cached_certificate(pem)
        key = normalize_pem(pem).to_s.dup.freeze
        CERTIFICATE_CACHE_LOCK.synchronize do
          return CERTIFICATE_CACHE[key] if CERTIFICATE_CACHE.key?(key)

          CERTIFICATE_CACHE.shift if CERTIFICATE_CACHE.size >= 32
          CERTIFICATE_CACHE[key] = parse_single_cert(key)
        end
      end
      private_class_method :cached_certificate

      PEM_CERT_BEGIN = '-----BEGIN CERTIFICATE-----'
      PEM_CERT_BLOCK = /-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m

      # The value must consist of ONE CERTIFICATE block and NOTHING ELSE
      # (surrounding whitespace tolerated). Counting BEGIN markers is not
      # enough: OpenSSL::X509::Certificate.new picks the first CERTIFICATE
      # block out of whatever surrounds it, so "cert + private key", "private
      # key + cert" and "junk + cert + junk" all parse. The value is stored
      # WHOLE as the record's idp_cert and served back in plaintext by the
      # SSO config API to every org admin (it is a public certificate, so the
      # serializer does not mask it) — a pasted bundle with the IdP's private
      # key after the certificate would be disclosed there. Only the exact
      # block is handed to OpenSSL, and only when it IS the whole value.
      #
      # @return [OpenSSL::X509::Certificate, String] the certificate, or the
      #   structural problem as a String
      def self.parse_single_cert(pem)
        text = normalize_pem(pem).to_s
        return 'IdP certificate is blank' if text.strip.empty?
        return 'IdP certificate must be a PEM X.509 certificate (-----BEGIN CERTIFICATE-----)' unless text.include?(PEM_CERT_BEGIN)

        # A BEGIN with no END (a truncated paste) is a parse failure, not a
        # count problem: OpenSSL refuses it too ("bad end line").
        blocks = text.scan(PEM_CERT_BLOCK)
        return 'IdP certificate does not parse as X.509' if blocks.empty?

        # One block, no second BEGIN inside it (a truncated block followed by
        # a complete one still parses in OpenSSL), and nothing around it.
        unless blocks.one? && text.scan(PEM_CERT_BEGIN).one? && text.strip == blocks.first.strip
          return 'IdP certificate must contain exactly one PEM certificate'
        end

        OpenSSL::X509::Certificate.new(blocks.first)
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

      # The session-cookie prerequisite (header: OPERATOR PREREQUISITE), as a
      # checkable rule. The HTTP-POST callback is a cross-site POST; a cookie
      # that is not SameSite=None is withheld on it, and a browser refuses a
      # SameSite=None cookie that is not also Secure. Either way the session
      # holding the pending AuthnRequest id is absent at the callback and
      # every sign-in ends as :saml_no_pending_request.
      #
      # ONE rule for three consumers: .platform_options (so the PLATFORM
      # provider is skipped at boot and not advertised — see the header),
      # the boot warning when the tenant PLACEHOLDER registers
      # (features/omniauth.rb configure_provider) and the tenant API's
      # save-time refusal (SamlFields#validate_saml_fields!). It is
      # deliberately NOT a rung in tenant_sso_unavailable_reason: that ladder
      # feeds sso_available_for_tenant_host? and the restrict_to pin, and a
      # rung here could re-enable password sign-in on an SSO-only host. The
      # platform placement has no such hazard: the platform advertised set
      # (AuthConfig#sso_providers) feeds restrict_to only through
      # restrict_to_unmet_prerequisite, which REFUSES BOOT when 'sso' is
      # restricted to and no provider is active — fail closed, never a
      # re-opened password form.
      #
      # @param session [Hash] the resolved session settings (Onetime.session_config)
      # @return [String, nil] problem description, or nil when compatible
      def self.session_cookie_problem(session = current_session_config)
        same_site = session['same_site'].to_s.strip.downcase
        secure    = session['secure'] == true
        return nil if same_site == 'none' && secure

        "site.session.same_site is #{same_site.empty? ? 'unset' : "'#{same_site}'"} " \
          "and secure is #{secure}; SAML needs same_site: none with secure: true, " \
          'or the session cookie is withheld on the cross-site HTTP-POST callback ' \
          'and every SAML sign-in is refused as saml_no_pending_request'
      end

      # @return [Hash] Onetime.session_config, or {} before boot has defined it
      def self.current_session_config
        return {} unless defined?(Onetime) && Onetime.respond_to?(:session_config)

        Onetime.session_config || {}
      end
      private_class_method :current_session_config

      # The canonical origin for the PLATFORM SAML surface:
      # `scheme://site.host`, with the scheme from site.ssl. Both platform SP
      # identifiers derive from it, so the ACS URL the AuthnRequest and the
      # SP metadata advertise, and the host whose session cookie holds the
      # pending request id, are the same host by construction at boot. Derived from
      # configuration, never from the request, and never by string-surgery
      # on the SP EntityID — SAML_SP_ENTITY_ID may be an opaque URN.
      #
      # @return [String] scheme://host[:port], no trailing slash
      # @raise [ArgumentError] when site.host is not configured
      def self.platform_base_url
        conf = defined?(OT) && OT.respond_to?(:conf) ? OT.conf : nil
        host = conf&.dig('site', 'host').to_s.strip
        if host.empty?
          raise ArgumentError, 'site.host is not configured, so no platform SAML SP URL can be derived'
        end

        scheme = conf.dig('site', 'ssl') == false ? 'http' : 'https'
        "#{scheme}://#{host}"
      end

      # Our SP EntityID on the PLATFORM surface: SAML_SP_ENTITY_ID when set,
      # otherwise .platform_base_url + the strategy's request path +
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

        base = begin
          platform_base_url
        rescue ArgumentError
          raise ArgumentError,
            'SAML_SP_ENTITY_ID is unset and site.host is not configured, so no SP EntityID can be derived'
        end

        "#{base}/auth/sso/#{route_name}/metadata"
      end

      # Our ACS URL on the PLATFORM surface: .platform_base_url + the
      # strategy's callback path. Pinned into the strategy options by
      # .platform_options so omniauth-saml never falls back to the
      # request-derived RequestBoundSAML#callback_url for this surface. There
      # is no env override: the ACS is where the browser POSTs the response,
      # so it can only ever be a URL this application serves, and the IdP
      # compares it against the AuthnRequest's AssertionConsumerServiceURL.
      #
      # @param route_name [String] the configured route name (SAML_ROUTE_NAME)
      # @return [String]
      # @raise [ArgumentError] when site.host is not configured
      def self.platform_acs_url(route_name)
        "#{platform_base_url}/auth/sso/#{route_name}/callback"
      end

      # Is +host+ the boot-pinned platform SAML host — the hostname of
      # .platform_base_url, where .platform_acs_url lands? Port- and
      # case-insensitive, through the same normalizer
      # DomainStrategy.canonical_host? admits a candidate with, so a
      # `site.host` configured as an authority (localhost:7143) matches a
      # request that arrives as `localhost`. False when site.host is not
      # configured (there is no platform SAML host to be).
      #
      # Descriptive, not a serving gate: platform SAML is ALSO served on a
      # verified custom domain under platform fallback, where
      # Auth::Config::Hooks::OmniAuthTenant.bind_platform_fallback_acs
      # rebinds the ACS per request (keyed on Auth::PublicHost.resolve). This
      # predicate names only the host the ACS is pinned to at boot.
      #
      # NARROWER than DomainStrategy.canonical_host? on purpose: that
      # predicate covers the whole canonical SET (features.domains.default,
      # link_domains), and a split deployment's secondary canonical host is
      # NOT the ACS host — a sign-in started there ends as
      # :saml_acs_host_mismatch like any other off-host start.
      #
      # @param host [String, nil] a hostname, with or without a port
      # @return [Boolean]
      def self.platform_host?(host)
        # Resolved lazily, like csp_origin_for: this file stays loadable
        # without the application's utils.
        require 'onetime/utils/domain_parser' unless defined?(Onetime::Utils::DomainParser)

        candidate = Onetime::Utils::DomainParser.extract_hostname(host.to_s)
        return false if candidate.nil?

        platform = Onetime::Utils::DomainParser.extract_hostname(URI.parse(platform_base_url).host.to_s)
        !platform.nil? && candidate.casecmp?(platform)
      rescue ArgumentError, URI::Error
        false
      end

      # Platform strategy options from the env. Raises ArgumentError (caught by
      # configure_provider, mirrored by .platform_usable?) with a message that
      # names the offending variable or setting.
      #
      # The session cookie is checked FIRST: it is an install-level
      # prerequisite that no SAML_* value can satisfy, so it is the problem
      # an operator has to fix before any other one is worth reporting, and
      # it is a Hash read where the trio costs an X.509 parse (this runs per
      # request via .platform_usable?).
      #
      # @return [Hash]
      def self.platform_options
        cookie_problem = session_cookie_problem
        raise ArgumentError, cookie_problem unless cookie_problem.nil?

        options = begin
          strategy_options_for(
            idp_sso_service_url: ENV.fetch('SAML_IDP_SSO_SERVICE_URL', nil),
            idp_entity_id: ENV.fetch('SAML_IDP_ENTITY_ID', nil),
            idp_cert: ENV.fetch('SAML_IDP_CERT', nil),
            uid_attribute: ENV.fetch('SAML_UID_ATTRIBUTE', nil),
            name_id_format: ENV.fetch('SAML_NAME_ID_FORMAT', PERSISTENT_NAME_ID_FORMAT),
          )
        rescue ArgumentError => ex
          raise ArgumentError,
            "#{ex.message} (check SAML_IDP_SSO_SERVICE_URL, SAML_IDP_ENTITY_ID, SAML_IDP_CERT, SAML_NAME_ID_FORMAT)"
        end

        route_name                               = ENV.fetch('SAML_ROUTE_NAME', 'saml')
        options[:sp_entity_id]                   = platform_sp_entity_id(route_name)
        options[:assertion_consumer_service_url] = platform_acs_url(route_name)
        options
      end

      # Is the platform provider not just SET but USABLE — the SAML_* vars
      # valid, an SP EntityID and ACS URL derivable, and the session cookie
      # SAML-compatible? The :vars_valid predicate (see the registry header
      # for why the advertised and registered provider sets need one shared
      # answer). Runs per request on the serializer and HttpOrigin paths; one
      # X.509 parse, no I/O.
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
        # Platform fallback may rebind only the ACS after Auth::PublicHost
        # verifies the custom request host. EntityID and IdP trust stay pinned.
        request_bound_platform_acs: true,
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
