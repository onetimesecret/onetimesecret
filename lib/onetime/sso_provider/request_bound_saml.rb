# lib/onetime/sso_provider/request_bound_saml.rb
#
# frozen_string_literal: true

# OmniAuth::Strategies::RequestBoundSAML — the only SAML strategy this
# application registers (#4450). A subclass of omniauth-saml's strategy that
# owns every SAML-specific gate.
#
# WHY A SUBCLASS
#
#   omniauth-saml + ruby-saml validate the DOCUMENT (signature, audience,
#   recipient, validity window). They leave the things that bind a valid
#   document to THIS login attempt, and to THIS identity provider, to the
#   application — and with defaults that accept rather than refuse:
#
#     1. InResponseTo is not checked at all unless the app passes
#        :matches_request_id, and the gem never stores the AuthnRequest id it
#        generated, so there is nothing to pass. Every response is accepted
#        as if unsolicited ("IdP-initiated SSO"), which lets an attacker
#        deliver THEIR valid response to a victim's browser (login CSRF /
#        session fixation into the attacker's account).
#     2. Issuer validation is skipped when settings.idp_entity_id is nil
#        (ruby-saml response.rb validate_issuer), and audience validation is
#        skipped when sp_entity_id is blank (validate_audience). The app keys
#        every SSO identity on (issuer, uid) — see
#        Auth::Config::Features::OmniAuth.resolve_issuer — so a SAML login
#        with no proven issuer has no safe identity key at all.
#     3. A `transient` NameID is, by definition, a fresh random value per
#        login. Used as the uid it mints a new account on every sign-in.
#     4. Nothing stops a second presentation of the same assertion inside
#        its validity window.
#     5. The auth hash's `extra` carries the live ruby-saml Response object:
#        the settings (SP private key when one is configured, IdP cert) and
#        the full response XML. Anything that inspects, logs, marshals or
#        session-stores the auth hash leaks it.
#     6. The gem writes session['saml_uid'] / session['saml_session_index']
#        on every successful callback for its SLO endpoints. SLO is off here
#        (slo_enabled: false), so nothing reads them.
#     7. The verifier accepts whichever signature and digest algorithm the
#        response declares — a SHA-1 signed response verifies exactly like a
#        SHA-256 one, and the SECURITY hash cannot change that (its
#        digest/signature_method are SP-side signing parameters).
#
#   rodauth-omniauth's before_omniauth_callback_route has a single owner
#   (apps/web/auth/config/hooks/omniauth_tenant.rb) and Rodauth hooks do not
#   chain, so these gates cannot live in a hook without entangling them with
#   tenant resolution. In the strategy they run for the platform AND the
#   tenant surface identically, and a refusal is an ordinary OmniAuth
#   fail! — it lands on the existing omniauth_on_failure path
#   (apps/web/auth/config/hooks/omniauth.rb) and the user sees sso_failed.
#
# IdP-INITIATED SSO IS DELIBERATELY UNSUPPORTED. A callback with no pending
# AuthnRequest id in the session is refused. That is the point of (1), not a
# limitation to be worked around.
#
# EVERY GATE FAILS CLOSED. A blank option, an unreadable issuer, a missing
# assertion id, a datastore error in the replay cache — each is a refusal,
# never a fall-through to the gem's permissive default.
#
# NEVER log, inspect, marshal or session-store the ruby-saml Response or the
# gem's `extra`. Log events from this file carry scalars only.
#
# GEM INTERNALS THIS FILE DEPENDS ON — RE-VERIFY on any omniauth-saml or
# ruby-saml bump (ruby-saml is pinned exactly in the Gemfile for this reason).
# Verified against omniauth-saml 2.2.5 (`saml.rb`) and ruby-saml 1.18.1
# (`response.rb`, `settings.rb`):
#
#   - saml.rb:54-60   request_phase keeps the Authrequest local. We copy its
#                     body to capture `uuid`. If upstream adds behaviour to
#                     request_phase, port it here.
#   - saml.rb:62-74   callback_phase builds the Response through the PRIVATE
#                     options_for_response_object (saml.rb:273-282) and
#                     rescues both ValidationError classes into
#                     fail!(:invalid_ticket).
#   - saml.rb:168-182 PRIVATE handle_response(raw, opts, settings) sets
#                     soft = false, calls is_valid? (which therefore RAISES on
#                     the first failed check), assigns @name_id,
#                     @session_index, @attributes, @response_object, writes
#                     the two session keys, then yields to build the auth
#                     hash. We wrap that yield.
#   - saml.rb:132     `extra` DSL block exposes @response_object. OmniAuth
#                     deep-merges DSL blocks across ancestors, so a subclass
#                     `extra { }` block could only ADD keys; we override the
#                     instance method instead.
#   - response.rb:626-633 validate_in_response_to passes when
#                     :matches_request_id is absent OR nil — so we refuse a
#                     blank pending id ourselves before the gem ever runs.
#   - response.rb:305-327 `issuers` returns the uniq'd Response + Assertion
#                     Issuer strings and RAISES ValidationError when either
#                     element is missing or repeated.
#   - response.rb validate_issuer uses Utils.uri_match? (case-insensitive on
#                     scheme/host). We additionally require byte equality,
#                     because the configured value is what the identity is
#                     keyed on.
#   - xml_security.rb:93-110 `algorithm` maps the SignatureMethod /
#                     DigestMethod URI the RESPONSE declares to a digest class
#                     — and maps ANY URI it does not recognise to SHA1. The
#                     verifier (cache_referenced_xml :341, validate_signature
#                     :415) reads those URIs with REXML from the
#                     SignedDocument it validates (`document`, or
#                     `decrypted_document` for an encrypted assertion;
#                     response.rb doc_to_validate) and accepts whatever they
#                     name, so a SHA-1 signed response verifies under the
#                     hardened settings (SECURITY's digest/signature_method
#                     are SP-side signing parameters). signature_algorithm_
#                     refusal below reads the same attributes from the same
#                     REXML documents and refuses anything off its allowlist.
#   - settings.rb:280 idp_cert_fingerprint_algorithm defaults to SHA1, and
#                     xml_security.rb validate_document compares a
#                     response-embedded certificate with the pinned one by
#                     that fingerprint — then verifies with the EMBEDDED
#                     certificate. Saml.hardened_options pins SHA-256 there.
#   - saml.rb:88-109  other_phase runs setup_phase and then serves /metadata
#                     through the PRIVATE other_phase_for_metadata
#                     (saml.rb:284-293), which we wrap.
#   - omniauth strategy.rb:504-506 callback_url appends the request's query
#                     string; saml.rb:269 defaults the ACS URL to it.
#   - omniauth strategy.rb:138 instance options are DEEP-MERGED over class
#                     defaults, so an empty Hash option cannot clear a
#                     Hash-valued gem default (see
#                     idp_sso_service_url_runtime_params below).

require 'omniauth-saml'

require 'onetime/security/saml_assertion_replay_guard'
require 'onetime/sso_provider/ruby_saml_log_bridge'

# ruby-saml logs the full AuthnRequest XML at DEBUG to a STDOUT logger
# outside Rails (ruby-saml logging.rb:7-12, authrequest.rb:70). Re-point it
# the moment the gem is loaded, before any strategy instance can exist.
OneLogin::RubySaml::Logging.logger = Onetime::SsoProvider::RubySamlLogBridge

module OmniAuth
  module Strategies
    class RequestBoundSAML < OmniAuth::Strategies::SAML
      # The exception handed to fail! for refusals made by this subclass
      # rather than by the gem (never raised). A distinct class so the
      # failure hook's `error_class` log field tells the two apart; a
      # subclass of the gem's error so anything matching on that still does.
      class Refusal < OmniAuth::Strategies::SAML::ValidationError; end

      option :name, 'saml'

      # omniauth-saml defaults this to { RelayState: 'RelayState' }
      # (saml.rb:17): whatever ?RelayState= the user's browser sends to the
      # login route is forwarded to the IdP, which must echo it back. Nothing
      # here reads it (SLO is off), so there is no reason to let a login link
      # push attacker-chosen data through the IdP.
      #
      # It has to be cleared HERE, as a class default. OmniAuth deep-merges
      # instance options over the class defaults (strategy.rb:138), so passing
      # `idp_sso_service_url_runtime_params: {}` at registration merges an
      # empty hash into the gem's default and changes nothing.
      option :idp_sso_service_url_runtime_params, {}

      # Session key holding the one pending AuthnRequest id. String key: the
      # session is a string-keyed store at rest.
      REQUEST_ID_KEY = 'saml_authn_request_id'

      # Written by the gem on every successful callback (saml.rb:179-180) for
      # its SLO endpoints. SLO is disabled, so they are dead weight that
      # carries the IdP's NameID into every later request's session.
      GEM_SESSION_KEYS = %w[saml_uid saml_session_index].freeze

      TRANSIENT_NAME_ID_FORMAT = 'urn:oasis:names:tc:SAML:2.0:nameid-format:transient'

      DSIG_NS = 'http://www.w3.org/2000/09/xmldsig#'

      # The only XML-DSig algorithms a response may be signed with. An
      # ALLOWLIST on the exact URI string, never a denylist and never the
      # class ruby-saml resolves it to: xml_security.rb `algorithm` maps every
      # URI it does not recognise (and rsa-sha1, dsa-sha1, ...) to SHA1, so
      # "not in this list" is the only safe reading of "unknown". RSA-PSS
      # (xmldsig-more#sha256-rsa-MGF1 etc.) is deliberately absent: the gem
      # resolves it to a plain SHA-256 PKCS#1 v1.5 verify and it would fail
      # anyway. ECDSA is included because the same `verify` call works for an
      # EC public key. RE-VERIFY on a ruby-saml bump.
      ALLOWED_SIGNATURE_METHODS = %w[
        http://www.w3.org/2001/04/xmldsig-more#rsa-sha256
        http://www.w3.org/2001/04/xmldsig-more#rsa-sha384
        http://www.w3.org/2001/04/xmldsig-more#rsa-sha512
        http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256
        http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384
        http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512
      ].freeze

      ALLOWED_DIGEST_METHODS = %w[
        http://www.w3.org/2001/04/xmlenc#sha256
        http://www.w3.org/2001/04/xmldsig-more#sha384
        http://www.w3.org/2001/04/xmlenc#sha512
      ].freeze

      # Longest IdP-supplied string copied into a log event.
      LOG_VALUE_MAX = 200

      # Body copied from omniauth-saml saml.rb:54-60 (RE-VERIFY on bump), plus
      # the refusal guard and the one line that stores the request id.
      def request_phase
        if (blank = blank_trust_option)
          return refuse!(:saml_misconfigured, "SAML #{blank} is not configured", option: blank.to_s)
        end

        authn_request = OneLogin::RubySaml::Authrequest.new

        # Overwrites any earlier pending id: one login attempt at a time per
        # session. A second tab's request supersedes the first, and the first
        # tab's response is then refused (mismatch) — closed, and retryable.
        session[REQUEST_ID_KEY] = authn_request.uuid

        with_settings do |settings|
          redirect(authn_request.create(settings, additional_params_for_authn_request))
        end
      end

      def callback_phase
        # One-shot: consumed BEFORE anything is validated, so a response that
        # fails any later check still burns the pending id. `.to_s` because a
        # session store may hand back nil or (after a serializer round trip)
        # something that is not a String.
        @expected_request_id = session.delete(REQUEST_ID_KEY).to_s.strip

        # ruby-saml treats a nil :matches_request_id as "do not check"
        # (response.rb:628), so an empty pending id MUST be refused here.
        if @expected_request_id.empty?
          return refuse!(:saml_no_pending_request, 'No pending AuthnRequest for this session')
        end

        # Checked before the gem parses a single byte: with either value
        # blank the gem silently SKIPS issuer / audience validation.
        if (blank = blank_trust_option)
          return refuse!(:saml_misconfigured, "SAML #{blank} is not configured", option: blank.to_s)
        end

        super
      end

      # omniauth's default appends the current request's query string
      # (strategy.rb:504-506), and omniauth-saml defaults the ACS URL to this
      # value (saml.rb:269). The ACS URL is registered verbatim at the IdP and
      # compared against the response Destination/Recipient, so it must be a
      # constant: a login link carrying ?domain=... must not change it.
      # full_host is the application's public-host override (#4224) — never
      # derive this from request.host.
      def callback_url
        full_host + callback_path
      end

      # Replaces the gem's `extra` (saml.rb:132) wholesale: the auth hash
      # NEVER carries `response_object`. Scalars and a plain Hash only, string
      # keys, safe to inspect / marshal / serialize.
      #
      # `idp_entity_id` is the CONFIGURED EntityID, which post_validation_refusal
      # has proven byte-equal to the single Issuer of the validated response.
      # It is the SAML issuer for identity keying (resolve_issuer) — read it
      # from here, never from raw_info: every raw_info key is an attribute
      # name chosen by the IdP.
      def extra
        {
          'idp_entity_id' => options.idp_entity_id.to_s,
          'name_id_format' => @name_id_format.to_s,
          'session_index' => @session_index.to_s,
          'raw_info' => plain_attributes,
        }
      end

      private

      # saml.rb:273-282. Forces the InResponseTo check on, and strips every
      # ruby-saml `skip_*` escape hatch (skip_audience, skip_conditions,
      # skip_destination, skip_recipient_check, skip_subject_confirmation,
      # skip_authnstatement) so no option source — env, tenant record, a
      # future registry field — can switch a document check off.
      def options_for_response_object
        super
          .reject { |key, _| key.to_s.start_with?('skip_') }
          .merge(matches_request_id: @expected_request_id)
      end

      # saml.rb:284-293. The gem serves SP metadata from whatever options the
      # strategy holds. With the placeholder registration (org-level SSO on,
      # no platform SAML_* vars) and no tenant resolved — the canonical host,
      # or a tenant without a usable SsoConfig under platform fallback — that
      # is a document with a BLANK entityID: half-configured metadata an IdP
      # admin could import. Answer 404 instead; the same blank-trust-anchor
      # test that refuses both login phases. An unresolvable tenant WITHOUT
      # platform fallback never reaches here: the tenant setup hook has
      # already redirected (omniauth_tenant.rb handle_missing_tenant_config;
      # other_phase runs setup_phase first, saml.rb:88-91).
      def other_phase_for_metadata
        return Rack::Response.new('Not Found', 404, { 'content-type' => 'text/plain' }).finish if blank_trust_option

        super
      end

      # saml.rb:168-182. By the time the block runs the gem has validated the
      # document (is_valid? with soft = false raises otherwise), populated its
      # ivars and written its session keys. The block is where the gem builds
      # the auth hash and calls the app — so every gate below runs strictly
      # between "document is valid" and "anyone sees an auth hash".
      def handle_response(raw_response, opts, settings)
        super do
          GEM_SESSION_KEYS.each { |key| session.delete(key) }

          refusal = post_validation_refusal(@response_object, opts)
          next refuse!(*refusal[0..1], **refusal[2]) if refusal

          @name_id_format = @response_object.name_id_format
          yield
        end
      end

      # @return [Array(Symbol, String, Hash), nil] fail! type, message and
      #   scalar log fields — or nil when the response may proceed
      def post_validation_refusal(response, opts)
        # Belt and braces for the soft = false contract: if a future gem
        # version validated softly and ignored the result, the collected
        # errors are still here.
        unless response.errors.empty?
          return [:invalid_ticket, 'SAML response failed validation', { error_count: response.errors.size }]
        end

        signature_algorithm_refusal(response) ||
          issuer_refusal(response) ||
          name_id_refusal(response) ||
          replay_refusal(response, opts)
      end

      # Every ds:Signature in the document(s) ruby-saml validated must name
      # an allowlisted SignatureMethod, and every ds:Reference under it an
      # allowlisted DigestMethod. ruby-saml verifies with whatever the
      # response declares and resolves anything unfamiliar to SHA-1 (see the
      # header), so without this a SHA-1 signature — collision-capable since
      # 2017 — is as good as SHA-256.
      #
      # Read with REXML from `response.document` and, when the assertion was
      # encrypted, `response.decrypted_document`: the same parser, the same
      # SignedDocument objects and the same XPath shape the verifier used
      # (xml_security.rb:341 './ds:SignedInfo/ds:SignatureMethod', :415
      # './ds:DigestMethod' under the Reference) — never a fresh parse of the
      # raw parameter with another parser, which could see a different
      # Signature than the one that was verified. Gating EVERY signature
      # rather than locating the one the gem picked is a superset: a response
      # carrying any weak signature is refused, verified or not.
      #
      # A document with no Signature at all cannot reach here (the gem
      # requires one), so an empty read is treated as a refusal too.
      def signature_algorithm_refusal(response)
        documents = [response.document, response.decrypted_document].compact
        found     = 0

        documents.each do |doc|
          REXML::XPath.each(doc, '//ds:Signature', 'ds' => DSIG_NS) do |signature|
            found += 1

            signature_method = REXML::XPath.first(
              signature, './ds:SignedInfo/ds:SignatureMethod/@Algorithm', 'ds' => DSIG_NS
            )&.value.to_s
            unless ALLOWED_SIGNATURE_METHODS.include?(signature_method)
              return weak_algorithm_refusal('signature_method', signature_method)
            end

            REXML::XPath.each(signature, './ds:SignedInfo/ds:Reference', 'ds' => DSIG_NS) do |reference|
              digest_method = REXML::XPath.first(reference, './ds:DigestMethod/@Algorithm', 'ds' => DSIG_NS)&.value.to_s
              return weak_algorithm_refusal('digest_method', digest_method) unless ALLOWED_DIGEST_METHODS.include?(digest_method)
            end
          end
        end

        return weak_algorithm_refusal('signature_method', '') if found.zero?

        nil
      rescue StandardError => ex
        # An XPath surprise on a document the gem already accepted: refuse,
        # class name only.
        [:saml_weak_signature_algorithm, 'SAML signature algorithms could not be read', { error_class: ex.class.name }]
      end

      def weak_algorithm_refusal(kind, uri)
        [
          :saml_weak_signature_algorithm,
          'SAML response uses a signature or digest algorithm that is not allowed',
          { kind: kind, algorithm: loggable(uri) },
        ]
      end

      # Exactly one Issuer value across Response and Assertion, byte-equal to
      # the configured EntityID. Stricter than the gem's uri_match?, because
      # the configured string is what the identity row is keyed on: an IdP
      # that answers as "HTTPS://IDP.example.com" must not resolve to the
      # same identities as "https://idp.example.com" by accident of a
      # case-folding comparison we do not control.
      def issuer_refusal(response)
        expected = options.idp_entity_id.to_s
        begin
          issuers = response.issuers
        rescue OneLogin::RubySaml::ValidationError
          return [:saml_issuer_unreadable, 'SAML response Issuer is missing or repeated', {}]
        end

        unless issuers.is_a?(Array) && issuers.size == 1
          return [
            :saml_issuer_mismatch,
            'SAML response does not carry exactly one Issuer value',
            { issuer_count: Array(issuers).size },
          ]
        end

        return nil if issuers.first.is_a?(String) && issuers.first == expected

        [
          :saml_issuer_mismatch,
          'SAML response Issuer does not equal the configured IdP EntityID',
          { observed_issuer: loggable(issuers.first), expected_issuer: loggable(expected) },
        ]
      end

      # A transient NameID is a per-login random value; as a uid it would
      # provision a new account on every sign-in. Only acceptable when the
      # uid comes from a configured attribute instead. The uid itself must
      # never be blank either way (a missing uid_attribute raises inside the
      # gem's uid block → :invalid_ticket; this catches present-but-empty).
      def name_id_refusal(response)
        uses_attribute = !options.uid_attribute.to_s.strip.empty?

        if !uses_attribute && response.name_id_format.to_s.strip == TRANSIENT_NAME_ID_FORMAT
          return [
            :saml_transient_name_id,
            'SAML NameID is transient and no uid_attribute is configured',
            { name_id_format: TRANSIENT_NAME_ID_FORMAT },
          ]
        end

        return nil unless uid.to_s.strip.empty?

        [:saml_missing_uid, 'SAML response yields a blank uid', { uses_uid_attribute: uses_attribute }]
      end

      # Last gate, so a response refused for any other reason does not spend
      # a datastore write. See Onetime::Security::SamlAssertionReplayGuard.
      def replay_refusal(response, opts)
        assertion_id    = response.assertion_id.to_s
        not_on_or_after = response.not_on_or_after

        if assertion_id.strip.empty? || !not_on_or_after.is_a?(Time)
          return [
            :saml_assertion_unbounded,
            'SAML assertion has no ID or no NotOnOrAfter',
            { has_assertion_id: !assertion_id.strip.empty?, has_not_on_or_after: not_on_or_after.is_a?(Time) },
          ]
        end

        claimed = Onetime::Security::SamlAssertionReplayGuard.claim(
          idp_entity_id: options.idp_entity_id.to_s,
          assertion_id: assertion_id,
          not_on_or_after: not_on_or_after,
          clock_drift: opts[:allowed_clock_drift].to_f,
        )
        return nil if claimed == true

        [:saml_assertion_replayed, 'SAML assertion was already presented', {}]
      rescue StandardError => ex
        # FAIL CLOSED: a datastore outage (or any surprise from the guard)
        # must never become an unguarded login. Class name only — a Redis
        # error message can carry the connection URL.
        [:saml_replay_guard_unavailable, 'SAML replay guard is unavailable', { error_class: ex.class.name }]
      end

      # @return [Symbol, nil] the first blank trust-anchor option, if any
      def blank_trust_option
        [:idp_entity_id, :sp_entity_id].find { |key| options[key].to_s.strip.empty? }
      end

      # OneLogin::RubySaml::Attributes → plain Hash of name => Array<String>.
      # Drops the "fingerprint" key omniauth-saml injects (saml.rb:170; it is
      # not an IdP attribute, and it is the one non-Array value in there).
      # Values stay Arrays: that is what the IdP sent, and collapsing
      # single-valued attributes would make the shape depend on the data.
      def plain_attributes
        source = @attributes.respond_to?(:attributes) ? @attributes.attributes : nil
        return {} unless source.is_a?(Hash)

        source.each_with_object({}) do |(name, values), plain|
          next if name.to_s == 'fingerprint'

          plain[name.to_s] = Array(values).map { |value| value.nil? ? nil : value.to_s }
        end
      end

      # Every refusal the GEM makes — omniauth-saml's callback_phase rescues
      # both ValidationError classes into fail!(:invalid_ticket, $!)
      # (saml.rb:62-74) — arrives here with the gem's exception, and ruby-saml
      # builds those messages from the response: "Doesn't match the issuer,
      # expected: <x>, but was: <ISSUER>", "Invalid Audience ... <AUDIENCES>",
      # and Utils.status_error_msg appends the unsigned <StatusMessage>
      # verbatim (validate_success_status runs BEFORE validate_signature, so
      # no signature is needed to get there). The message is capped only by
      # the gem's 250,000-byte message_max_bytesize, and it would otherwise be
      # logged unbounded by omniauth's own logger, the application's
      # omniauth_on_failure hook and the audit event — a log-injection and
      # log-flooding surface open to anyone who can start a login.
      #
      # So a gem exception is swapped for a Refusal with a FIXED message, and
      # the gem's message reaches the log only through the same scalar-only,
      # bounded event this file's own refusals emit. Refusals made here pass
      # through untouched (they are already Refusals with fixed messages).
      # omniauth strategy.rb:542 `fail!(message_key, exception = nil)` —
      # RE-VERIFY the arity on an omniauth bump.
      def fail!(message_key, exception = nil)
        gem_refusal = exception.is_a?(OmniAuth::Strategies::SAML::ValidationError) ||
                      exception.is_a?(OneLogin::RubySaml::ValidationError)
        return super if !gem_refusal || exception.is_a?(Refusal)

        Onetime.get_logger('Auth').warn(
          '[saml_response_refused]',
          {
            reason: message_key.to_s,
            provider: name.to_s,
            phase: current_phase_label,
            error_class: exception.class.name,
            detail: loggable(exception.message),
          },
        )

        super(message_key, Refusal.new('SAML response failed validation'))
      end

      # fail! with a distinct type + one scalar-only log event. The exception
      # message is a fixed string from this file: omniauth logs it and the
      # application's omniauth_on_failure hook logs it again, so it must
      # never carry response content.
      def refuse!(type, message, **fields)
        GEM_SESSION_KEYS.each { |key| session.delete(key) }

        Onetime.get_logger('Auth').warn(
          '[saml_response_refused]',
          { reason: type.to_s, provider: name.to_s, phase: current_phase_label }.merge(fields),
        )

        fail!(type, Refusal.new(message))
      end

      def current_phase_label
        on_callback_path? ? 'callback' : 'request'
      end

      # One line, valid encoding, bounded: an IdP-supplied string may carry
      # newlines and control characters that would forge log lines.
      def loggable(value)
        value.to_s.scrub('?').gsub(/[[:cntrl:]]+/, ' ')[0, LOG_VALUE_MAX]
      end
    end
  end
end

# So a registry definition can name the strategy by symbol, the way every
# other provider does: `strategy: :request_bound_saml`.
OmniAuth.config.add_camelization 'request_bound_saml', 'RequestBoundSAML'
