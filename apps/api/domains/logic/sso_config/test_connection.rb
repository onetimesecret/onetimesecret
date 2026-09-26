# apps/api/domains/logic/sso_config/test_connection.rb
#
# frozen_string_literal: true

require 'json'
require 'time'
require_relative 'base'
require_relative '../../../../../lib/onetime/sso_provider/discovery_fetcher'
require_relative '../../../../../lib/onetime/sso_provider/discovery_issuer'
require_relative 'ssrf_protection'
require_relative 'saml_fields'

module DomainsAPI
  module Logic
    module SsoConfig
      # Test Domain SSO Connection
      #
      # @api Tests SSO configuration by validating IdP reachability and
      #   discovery document availability. This does NOT perform an actual
      #   OAuth flow or validate client credentials - it only confirms
      #   the IdP endpoint is accessible and properly configured.
      #
      #   For generic OIDC, the discovery document's `issuer` must equal the
      #   configured issuer exactly (OIDC Discovery 1.0 section 4.3; no
      #   trailing-slash or case normalization). A difference is reported as
      #   error_code 'issuer_mismatch' with details.configured_issuer and
      #   details.discovery_issuer. Entra ID has no operator-supplied issuer
      #   and is not compared.
      #
      #   Uses credentials from request body (not stored config) to allow
      #   testing before saving. Does not persist anything.
      #
      # Security Note:
      #   SSRF protection uses SsrfProtection module which validates URLs via
      #   DNS resolution against private/internal IP ranges. We intentionally
      #   do NOT use an IdP domain allowlist because:
      #   1. Organizations bring their own IdPs (custom OIDC, on-prem Entra, etc.)
      #   2. IP-based validation catches internal hosts regardless of hostname
      #   3. An allowlist would require maintenance and limit legitimate use cases
      #   See: ssrf_protection.rb for implementation details.
      #
      # SAML (#4450) is the exception to "reachability": its test is LOCAL
      #   validation only and makes no HTTP request. There is nothing to
      #   fetch — a SAML IdP has no discovery document this application
      #   consumes, and the SSO service URL is only ever visited by the user's
      #   browser. What can be checked without the IdP is checked: the SSO URL
      #   is a public https URL, the EntityID is usable as an identity issuer,
      #   and the certificate is one PEM X.509 certificate that has not
      #   expired (its expiry date is reported, because an expired signing
      #   certificate is the most common way a working SAML login stops).
      #
      # Request body:
      # - provider_type: Required. One of: oidc, entra_id, saml (issuerless
      #   providers were removed, #3902)
      # - client_id: Required for oidc and entra_id. Not used by saml.
      # - tenant_id: Required for entra_id provider
      # - issuer: Required for oidc provider (HTTPS URL)
      # - idp_sso_service_url, idp_entity_id, idp_cert: Required for saml.
      #   idp_cert_fingerprint (and its ruby-saml siblings) is refused.
      # - client_secret: Not used for testing (never sent over network)
      #
      # Response:
      # - success: Boolean indicating if connection was successful
      # - provider_type: The provider type tested
      # - message: Human-readable result description
      # - details: Provider-specific information or error details
      #
      class TestConnection < Base
        include SsrfProtection
        include SamlFields

        # Connection timeout in seconds
        CONNECTION_TIMEOUT = 10

        # Read timeout in seconds
        READ_TIMEOUT = 10

        USER_AGENT = 'OneTimeSecret-SSO-Test/1.0'

        # Required fields in OIDC discovery document
        REQUIRED_OIDC_FIELDS = %w[
          authorization_endpoint
          token_endpoint
          jwks_uri
          issuer
        ].freeze

        VALID_PROVIDER_TYPES = Onetime::CustomDomain::SsoConfig::PROVIDER_TYPES.freeze

        # details.error_code for a SAML field that fails local validation. An
        # expired certificate reports 'certificate_expired' instead.
        SAML_ERROR_CODES = {
          idp_sso_service_url: 'invalid_sso_url',
          idp_entity_id: 'invalid_entity_id',
          idp_cert: 'invalid_certificate',
        }.freeze

        def process_params
          @domain_id     = sanitize_identifier(params['extid'])
          @provider_type = sanitize_plain_text(params['provider_type'])
          @client_id     = params['client_id'].to_s.strip
          @tenant_id     = sanitize_plain_text(params['tenant_id'])
          @issuer        = sanitize_url(params['issuer'])
          process_saml_params
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Validate provider_type
          validate_provider_type

          # Never accepted, whatever the provider type (see SamlFields)
          reject_forbidden_saml_params!

          # Validate client_id (OAuth-family providers; SAML has none)
          validate_client_id

          # Validate provider-specific fields
          validate_provider_specific_fields
        end

        def process
          OT.ld "[TestConnection] Testing #{@provider_type} connection for domain #{@domain_id}"

          result = case @provider_type
                   when 'oidc'
                     test_oidc_connection
                   when 'entra_id'
                     test_entra_id_connection
                   when 'saml'
                     test_saml_configuration
                   else
                     { success: false, message: "Unsupported provider type: #{@provider_type}" }
                   end

          # Log result (without sensitive data)
          if result[:success]
            OT.info "[TestConnection] Connection test successful for #{@provider_type}",
              { domain_id: @domain_id, provider_type: @provider_type }
          else
            OT.info "[TestConnection] Connection test failed for #{@provider_type}",
              { domain_id: @domain_id, provider_type: @provider_type, error: result[:message] }
          end

          success_data(result)
        end

        def success_data(result = {})
          {
            user_id: cust.extid,
            **result,
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
            provider_type: @provider_type,
            client_id: @client_id,
            tenant_id: @tenant_id,
            issuer: @issuer,
            idp_sso_service_url: @idp_sso_service_url,
            idp_entity_id: @idp_entity_id,
          }
        end

        private

        def validate_provider_type
          raise_form_error('Provider type is required', field: :provider_type, error_type: :missing) if @provider_type.to_s.empty?

          return if VALID_PROVIDER_TYPES.include?(@provider_type)

          raise_form_error(
            "Invalid provider type. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
            field: :provider_type,
            error_type: :invalid,
          )
        end

        def validate_client_id
          return unless Onetime::CustomDomain::SsoConfig.client_credentials?(@provider_type)

          raise_form_error('Client ID is required', field: :client_id, error_type: :missing) if @client_id.to_s.empty?
        end

        def validate_provider_specific_fields
          case @provider_type
          when 'oidc'
            validate_oidc_fields
          when 'entra_id'
            validate_entra_id_fields
          when 'saml'
            validate_saml_presence
          end
        end

        # Presence only. A MISSING field is a malformed request (form error,
        # like the other providers' required fields); an INVALID one is a
        # test result, reported by test_saml_configuration with an error_code
        # the form can render next to the right input.
        def validate_saml_presence
          saml_submitted.each do |field, value|
            next unless value.empty?

            raise_form_error("#{saml_label(field)} is required for SAML provider", field: field, error_type: :missing)
          end
        end

        def validate_oidc_fields
          if @issuer.to_s.empty?
            raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing)
          end

          unless @issuer.start_with?('https://')
            raise_form_error('Issuer URL must use HTTPS', field: :issuer, error_type: :invalid)
          end
        end

        def validate_entra_id_fields
          if @tenant_id.to_s.empty?
            raise_form_error('Tenant ID is required for Entra ID provider', field: :tenant_id, error_type: :missing)
          end

          # Validate tenant_id is UUID format
          uuid_regex = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
          return if @tenant_id.match?(uuid_regex)

          raise_form_error(
            'Tenant ID must be a valid UUID',
            field: :tenant_id,
            error_type: :invalid,
          )
        end

        # ──────────────────────────────────────────────────────────────────────────
        # Provider-specific connection tests
        # ──────────────────────────────────────────────────────────────────────────

        def test_oidc_connection
          discovery_url = build_discovery_url(@issuer)

          # SSRF prevention: validate URL host
          unless valid_issuer_host?(discovery_url)
            return {
              success: false,
              provider_type: @provider_type,
              message: 'Invalid issuer URL',
              details: {
                error_code: 'invalid_issuer',
                description: 'The issuer URL is not valid or uses an unsupported protocol',
              },
            }
          end

          fetch_and_validate_discovery(discovery_url, 'OIDC')
        end

        def test_entra_id_connection
          discovery_url = "https://login.microsoftonline.com/#{@tenant_id}/v2.0/.well-known/openid-configuration"
          fetch_and_validate_discovery(discovery_url, 'Entra ID')
        end

        # Local validation only — see the class comment. No network request is
        # made (the SSRF host check resolves the SSO URL's hostname, nothing
        # more). The same checks, in the same order, that PUT/PATCH apply
        # (SamlFields#saml_problem, preceded by the install's session-cookie
        # rule), so "test passes" means "save will accept".
        def test_saml_configuration
          cookie_problem = Onetime::SsoProvider::Saml.session_cookie_problem
          unless cookie_problem.nil?
            return {
              success: false,
              provider_type: @provider_type,
              message: "SAML sign-in cannot complete on this install: #{cookie_problem}",
              details: {
                error_code: 'session_cookie_incompatible',
                field: 'provider_type',
                description: cookie_problem,
              },
            }
          end

          saml_submitted.each do |field, value|
            problem = saml_problem(field, value)
            next if problem.nil?

            # A parseable certificate refused for its validity WINDOW gets a
            # window-specific code plus both bounds, so the UI can say when
            # it expired or when it becomes valid (ruby-saml drops a
            # certificate outside the window either way — Saml.cert_problem).
            cert       = field == :idp_cert ? Onetime::SsoProvider::Saml.parse_cert(value) : nil
            now        = Time.now
            not_after  = cert&.not_after
            not_before = cert&.not_before
            error_code = if !not_after.nil? && not_after < now
                           'certificate_expired'
                         elsif !not_before.nil? && not_before > now
                           'certificate_not_yet_valid'
                         else
                           SAML_ERROR_CODES.fetch(field)
                         end

            return {
              success: false,
              provider_type: @provider_type,
              message: problem,
              details: {
                error_code: error_code,
                field: field.to_s,
                description: problem,
                certificate_not_before: not_before&.utc&.iso8601,
                certificate_not_after: not_after&.utc&.iso8601,
              }.compact,
            }
          end

          validate_saml_policy!
          cert = Onetime::SsoProvider::Saml.parse_cert(@idp_cert)

          {
            success: true,
            provider_type: @provider_type,
            message: 'SAML configuration is valid (checked locally; the identity provider was not contacted)',
            details: {
              idp_entity_id: @idp_entity_id,
              idp_sso_service_url: @idp_sso_service_url,
              certificate_subject: cert.subject.to_utf8,
              certificate_not_after: cert.not_after.utc.iso8601,
              certificate_expires_in_days: ((cert.not_after - Time.now) / 86_400).floor,
            },
          }
        end

        # ──────────────────────────────────────────────────────────────────────────
        # Discovery document handling
        # ──────────────────────────────────────────────────────────────────────────

        def build_discovery_url(issuer)
          Onetime::SsoProvider::DiscoveryFetcher.discovery_url_for(issuer)
        end

        # Fetches through the shared SSRF-safe discovery fetcher and maps its
        # Result onto this endpoint's error_code vocabulary.
        #
        # The fetcher is the SSRF enforcement point: it resolves + validates
        # the host once via Onetime::Http::Guard and pins every dial to a
        # validated IP. That covers every caller — including
        # test_entra_id_connection, which never passes through
        # valid_issuer_host? (that check remains upstream as a cheap early
        # rejection with a friendly message).
        def fetch_and_validate_discovery(url, provider_name)
          fetched = discovery_fetcher.fetch(url)

          case fetched.status
          when :ok
            validate_discovery_response(fetched, provider_name)
          when :not_found
            failure(
              "#{provider_name} discovery document not found",
              error_code: 'discovery_not_found',
              http_status: fetched.http_status,
              url: url,
            )
          when :http_error
            failure(
              "#{provider_name} discovery request failed",
              error_code: 'http_error',
              http_status: fetched.http_status,
              description: fetched.http_message,
            )
          when :too_large
            failure(
              "#{provider_name} discovery document is too large",
              error_code: 'discovery_too_large',
              max_bytes: discovery_fetcher.max_bytes,
              url: url,
            )
          when :timeout
            failure(
              "#{provider_name} connection timed out",
              error_code: 'timeout',
              timeout_seconds: CONNECTION_TIMEOUT,
              url: url,
            )
          when :ssl_error
            failure(
              "#{provider_name} SSL/TLS error",
              error_code: 'ssl_error',
              description: sanitize_error_message(fetched.error&.message),
            )
          when :connection_failed
            failure(
              "#{provider_name} connection failed",
              error_code: 'connection_failed',
              description: sanitize_error_message(fetched.error&.message),
            )
          when :blocked
            # Deliberately generic: Blocked#message carries the resolved IP,
            # which must not be echoed back to the caller (information
            # disclosure about internal address space).
            failure(
              "#{provider_name} issuer resolves to a blocked address",
              error_code: 'blocked_target',
              description: 'The issuer host resolves to an address that is not allowed.',
            )
          when :invalid_url
            failure(
              'Invalid issuer URL',
              error_code: 'invalid_issuer',
              description: 'The issuer URL is not valid or uses an unsupported protocol',
            )
          else
            unexpected_failure(provider_name, fetched.error)
          end
        rescue StandardError => ex
          unexpected_failure(provider_name, ex)
        end

        def discovery_fetcher
          @discovery_fetcher ||= Onetime::SsoProvider::DiscoveryFetcher.new(
            open_timeout: CONNECTION_TIMEOUT,
            read_timeout: READ_TIMEOUT,
            user_agent: USER_AGENT,
          )
        end

        def failure(message, **details)
          {
            success: false,
            provider_type: @provider_type,
            message: message,
            details: details,
          }
        end

        def unexpected_failure(provider_name, error)
          OT.le "[TestConnection] Unexpected error testing #{provider_name}: #{error&.class&.name} - #{error&.message}"
          failure(
            "#{provider_name} connection error",
            error_code: 'unexpected_error',
            description: 'An unexpected error occurred. Please try again.',
          )
        end

        # @param fetched [Onetime::SsoProvider::DiscoveryFetcher::Result]
        def validate_discovery_response(fetched, provider_name)
          # Parse JSON
          discovery = JSON.parse(fetched.body)

          # Check required fields
          missing_fields = REQUIRED_OIDC_FIELDS.reject { |field| discovery.key?(field) && !discovery[field].to_s.empty? }

          unless missing_fields.empty?
            return {
              success: false,
              provider_type: @provider_type,
              message: "#{provider_name} discovery document is missing required fields",
              details: {
                error_code: 'invalid_discovery',
                missing_fields: missing_fields,
              },
            }
          end

          # Generic OIDC only: the operator-supplied issuer must equal the
          # discovered one exactly, or the IdP's ID tokens will never
          # validate. Entra's discovery URL is built from the tenant ID and
          # there is no operator-supplied issuer to compare against.
          if @provider_type == 'oidc'
            issuer_check = Onetime::SsoProvider::DiscoveryIssuer.check(
              configured: @issuer,
              discovered: discovery['issuer'],
            )
            return issuer_mismatch_failure(issuer_check, provider_name) unless issuer_check.ok?
          end

          # Success - return key endpoints
          {
            success: true,
            provider_type: @provider_type,
            message: "#{provider_name} connection successful",
            details: {
              issuer: discovery['issuer'],
              authorization_endpoint: discovery['authorization_endpoint'],
              token_endpoint: discovery['token_endpoint'],
              jwks_uri: discovery['jwks_uri'],
              userinfo_endpoint: discovery['userinfo_endpoint'],
              scopes_supported: discovery['scopes_supported']&.first(5), # Limit to first 5
            },
          }
        rescue JSON::ParserError
          {
            success: false,
            provider_type: @provider_type,
            message: "#{provider_name} returned invalid JSON",
            details: {
              error_code: 'invalid_json',
              content_type: fetched.content_type,
            },
          }
        end

        def issuer_mismatch_failure(issuer_check, provider_name)
          failure(
            "#{provider_name} issuer mismatch: the discovery document declares a different " \
            'issuer than the one configured. Issuer identifiers are compared exactly, ' \
            'including any trailing slash (Auth0, for example, uses a trailing slash). ' \
            'Set the issuer to the exact value the discovery document declares.',
            error_code: 'issuer_mismatch',
            configured_issuer: issuer_check.configured,
            discovery_issuer: issuer_check.discovered_string,
          )
        end

        def sanitize_error_message(message)
          # Remove potentially sensitive information from error messages
          message.to_s.gsub(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, '[IP]')
            .gsub(/:[0-9]+/, ':[PORT]')
            .slice(0, 200) # Limit length
        end
      end
    end
  end
end
