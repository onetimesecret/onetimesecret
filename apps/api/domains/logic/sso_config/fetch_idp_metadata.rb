# apps/api/domains/logic/sso_config/fetch_idp_metadata.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative 'discovery_check'
require_relative 'saml_fields'
require_relative 'ssrf_protection'
require_relative '../../../../../lib/onetime/sso_provider/discovery_fetcher'
require_relative '../../../../../lib/onetime/sso_provider/idp_metadata'
require 'onetime/security/sso_metadata_fetch_rate_limiter'

module DomainsAPI
  module Logic
    module SsoConfig
      # Fetch a SAML IdP metadata document for the settings form
      #
      # @api Fetches the SAML 2.0 IdP metadata at metadata_url and returns the
      #   values the form can prefill: the IdP EntityID, the HTTP-Redirect SSO
      #   URL, every signing certificate (with subject, validity window,
      #   SHA-256 fingerprint and a SHA-1 thumbprint for matching the Entra
      #   portal), and the NameID formats the IdP advertises
      #   (docs/specs/sso/saml-idp-metadata-consumption.md, Phase 1).
      #
      #   A PREVIEW, nothing more. The endpoint never reads or writes the SSO
      #   record: the admin reviews the values, picks a certificate, applies
      #   them to the form and saves through PutSsoConfig / PatchSsoConfig,
      #   which validate the trio exactly as they do pasted values. So no
      #   new trust is established here, and a fetched document is never
      #   applied on its own.
      #
      # Request body:
      # - metadata_url: Required. Public https:// URL of the metadata (Entra:
      #   the App Federation Metadata Url, which carries ?appid=...).
      #
      # Guards, in order (each a 4xx form error, as TestConnection's): a
      # session, the domain id, domain ownership and the organization's
      # manage_sso entitlement (authorize_domain_sso!), the install-wide
      # SAML switch (SamlFields#reject_saml_disabled!: with SAML off nothing
      # fetched could be saved), a nonblank metadata_url, and LAST the
      # per-customer rate limit (Onetime::Security::SsoMetadataFetchRateLimiter,
      # kind `sso_metadata_fetch`, 30 per hour by default; over the cap the
      # API answers 429 with retry_after), so a request the guards refuse
      # costs nothing. A URL refused by the structural or SSRF host check is
      # still charged: the host check resolves the caller-chosen name.
      #
      # Response (HTTP 200 either way):
      # - success: true, metadata_url (as submitted, stripped), idp_entity_id,
      #   idp_sso_service_url, signing_certificates, name_id_formats,
      #   problems — see Onetime::SsoProvider::IdpMetadata::Result#to_api_h.
      #   success means the document was fetched and parsed, NOT that it is
      #   importable: a `blocking` problem (no HTTP-Redirect endpoint, no
      #   usable signing certificate, an EntityID or SSO URL the save would
      #   refuse) means the trio must not be applied; an `advisory` one
      #   (unreadable_signing_certificates, tenant_level_entra_metadata) is a
      #   warning.
      # - success: false, metadata_url, message, details: { error_code,
      #   description, ... } for a URL refused before fetching
      #   (invalid_metadata_url), a fetch outcome (blocked_target, timeout,
      #   ssl_error, connection_failed, http_error, metadata_not_found,
      #   metadata_too_large), a document the parser refuses
      #   (invalid_metadata, aggregate_metadata, unreadable_certificate), or
      #   unexpected_error. The vocabulary is DiscoveryCheck's, with the
      #   metadata names.
      #
      # Egress: one GET through Onetime::SsoProvider::DiscoveryFetcher, the
      # SSRF enforcement point shared with DiscoveryCheck (host resolved once
      # through Onetime::Http::Guard, every dial pinned, no proxy,
      # VERIFY_PEER, no redirects, total deadline, 256 KiB body cap).
      # valid_issuer_host? runs first as the cheap early rejection, exactly
      # as for an OIDC issuer: unlike the SAML SSO URL, this URL IS fetched
      # by the server. The response Content-Type is not checked; the parser
      # is the gate.
      #
      # Never logs the URL or a certificate: the info line carries the
      # domain, the outcome code and problem codes only.
      #
      class FetchIdpMetadata < Base
        include SsrfProtection
        include SamlFields
        include Onetime::Security::SsoMetadataFetchRateLimiter

        # The fetch budget TestConnection's discovery fetch has.
        CONNECTION_TIMEOUT = DiscoveryCheck::CONNECTION_TIMEOUT
        READ_TIMEOUT       = DiscoveryCheck::READ_TIMEOUT

        USER_AGENT = 'OneTimeSecret-SSO-Metadata/1.0'

        # The SAML metadata media type (SAML 2.0 Metadata, section 4.1.1)
        # first, then what IdPs actually serve. Advisory only (see the
        # header): the fetcher never checks the response against it.
        ACCEPT = 'application/samlmetadata+xml, application/xml, text/xml'

        INVALID_URL_DESCRIPTION = 'The metadata URL must be a public https:// URL with a plain hostname, ' \
                                  'no credentials and no fragment.'

        PARSE_FAILURE_DESCRIPTIONS = {
          invalid_metadata: 'The response could not be read as SAML 2.0 identity provider metadata.',
          aggregate_metadata: 'The document lists more than one identity provider. Use the metadata URL ' \
                              'of the single identity provider this domain signs in with.',
          unreadable_certificate: 'The certificate in this metadata could not be read as an X.509 certificate. ' \
                                  'Copy the signing certificate from the identity provider instead.',
        }.freeze

        def process_params
          @domain_id    = sanitize_identifier(params['extid'])
          @metadata_url = params['metadata_url'].to_s.strip
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Nothing fetched can be saved while SAML is off on the install.
          reject_saml_disabled!

          raise_form_error('Metadata URL is required', field: :metadata_url, error_type: :missing) if @metadata_url.empty?

          # Last, so a request the guards above refuse is not charged. The URL
          # checks in #process resolve DNS, so a URL they refuse is.
          enforce_sso_metadata_fetch_rate_limit!(cust.extid)
        end

        def process
          OT.ld "[FetchIdpMetadata] Fetching SAML IdP metadata for domain #{@domain_id}"

          result = fetch_metadata
          log_outcome(result)

          success_data(result)
        end

        def success_data(result = {})
          {
            user_id: cust.extid,
            **result,
          }
        end

        def form_fields
          { domain_id: @domain_id, metadata_url: @metadata_url }
        end

        private

        def fetch_metadata
          return invalid_url_failure unless metadata_url_acceptable?

          fetched = metadata_fetcher.fetch(@metadata_url)
          return parse_metadata(fetched) if fetched.status == :ok

          fetch_failure(fetched)
        rescue StandardError => ex
          unexpected_failure(ex)
        end

        # The rule the save path applies to a new idp_metadata_url
        # (SamlFields#validate_idp_metadata_url!): structural, then the SSRF
        # host check.
        def metadata_url_acceptable?
          Onetime::SsoProvider::IdpMetadata.metadata_url_problem(@metadata_url).nil? &&
            valid_issuer_host?(@metadata_url)
        end

        # Raises only for something the parser's error boundary does not own
        # (Onetime::SsoProvider::IdpMetadata, ERROR BOUNDARY), which
        # #fetch_metadata reports as unexpected_error.
        def parse_metadata(fetched)
          parsed = Onetime::SsoProvider::IdpMetadata.parse(fetched.body, metadata_url: @metadata_url)
          { success: true, metadata_url: @metadata_url, **parsed.to_api_h }
        rescue Onetime::SsoProvider::IdpMetadata::Error => ex
          @parse_failure_reason = ex.reason
          failure(
            ex.message,
            error_code: ex.code.to_s,
            description: PARSE_FAILURE_DESCRIPTIONS.fetch(ex.code),
          )
        end

        # Maps a non-ok DiscoveryFetcher::Result onto the error vocabulary,
        # in DiscoveryCheck#fetch_and_validate_discovery's words.
        def fetch_failure(fetched)
          case fetched.status
          when :not_found
            failure(
              'IdP metadata document not found',
              error_code: 'metadata_not_found',
              description: 'The metadata URL answered 404 Not Found.',
              http_status: fetched.http_status,
            )
          when :http_error
            # A 3xx lands here too: redirects are reported, never followed.
            failure(
              'IdP metadata request failed',
              error_code: 'http_error',
              description: "The metadata URL answered HTTP #{fetched.http_status}.",
              http_status: fetched.http_status,
            )
          when :too_large
            failure(
              'IdP metadata document is too large',
              error_code: 'metadata_too_large',
              description: "The metadata document is larger than #{metadata_fetcher.max_bytes} bytes.",
              max_bytes: metadata_fetcher.max_bytes,
            )
          when :timeout
            failure(
              'IdP metadata request timed out',
              error_code: 'timeout',
              description: 'The metadata host did not answer in time.',
              timeout_seconds: CONNECTION_TIMEOUT,
            )
          when :ssl_error
            failure(
              'IdP metadata SSL/TLS error',
              error_code: 'ssl_error',
              description: sanitized_description(fetched.error, 'The TLS connection to the metadata host failed.'),
            )
          when :connection_failed
            failure(
              'IdP metadata connection failed',
              error_code: 'connection_failed',
              description: sanitized_description(fetched.error, 'The metadata host could not be reached.'),
            )
          when :blocked
            # Deliberately generic: Blocked#message carries the resolved IP,
            # which must not be echoed back to the caller (information
            # disclosure about internal address space).
            failure(
              'IdP metadata host resolves to a blocked address',
              error_code: 'blocked_target',
              description: 'The metadata host resolves to an address that is not allowed.',
            )
          when :invalid_url
            invalid_url_failure
          else
            unexpected_failure(fetched.error)
          end
        end

        def metadata_fetcher
          @metadata_fetcher ||= Onetime::SsoProvider::DiscoveryFetcher.new(
            open_timeout: CONNECTION_TIMEOUT,
            read_timeout: READ_TIMEOUT,
            user_agent: USER_AGENT,
            accept: ACCEPT,
          )
        end

        def invalid_url_failure
          failure('Invalid metadata URL', error_code: 'invalid_metadata_url', description: INVALID_URL_DESCRIPTION)
        end

        # Class name and the raising line only: the message of an error this
        # endpoint did not anticipate may carry document content.
        def unexpected_failure(error)
          @unexpected_error = error&.class&.name
          OT.le "[FetchIdpMetadata] Unexpected error fetching IdP metadata for domain #{@domain_id}: " \
                "#{@unexpected_error} at #{error&.backtrace_locations&.first}"
          failure(
            'IdP metadata fetch error',
            error_code: 'unexpected_error',
            description: 'An unexpected error occurred. Please try again.',
          )
        end

        def failure(message, **details)
          {
            success: false,
            metadata_url: @metadata_url,
            message: message,
            details: details,
          }
        end

        # The TLS / socket error text with addresses and ports masked and the
        # length capped, by the discovery check's own rule.
        def sanitized_description(error, fallback)
          text = DiscoveryCheck.sanitize_error_message(error&.message)
          text.strip.empty? ? fallback : text
        end

        # Scalars only: never the URL, a PEM or a message built from the
        # document.
        def log_outcome(result)
          fields = { domain_id: @domain_id, success: result[:success] }
          if result[:success]
            fields[:problems]          = result[:problems].map { it[:code] }
            fields[:certificate_count] = result[:signing_certificates].size
          else
            fields[:error_code] = result.dig(:details, :error_code)
            fields[:reason]     = @parse_failure_reason || @unexpected_error
          end

          OT.info '[FetchIdpMetadata] IdP metadata fetch completed', **fields.compact
        end
      end
    end
  end
end
