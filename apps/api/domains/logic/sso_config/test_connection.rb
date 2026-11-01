# apps/api/domains/logic/sso_config/test_connection.rb
#
# frozen_string_literal: true

require 'time'
require_relative 'base'
require_relative '../../../../../lib/onetime/sso_provider/entra'
require_relative 'discovery_check'
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
      #   testing before saving. Does not persist anything. The request's
      #   client_secret is never read. To check the SAVED record, including
      #   whether Entra accepts the stored client secret, see RunDiagnostics
      #   (POST /:extid/sso/diagnostics).
      #
      # Security Note:
      #   The discovery fetch and its SSRF protection live in DiscoveryCheck,
      #   shared with RunDiagnostics. See discovery_check.rb and
      #   ssrf_protection.rb.
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
        include DiscoveryCheck
        include SamlFields

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

          # The request's selection is what gets tested, not the stored one (#4764).
          @token_endpoint_auth_method = normalize_token_endpoint_auth_method(params['token_endpoint_auth_method'])
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
            token_endpoint_auth_method: @token_endpoint_auth_method,
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
          raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing) if @issuer.to_s.empty?
          raise_form_error('Issuer URL must use HTTPS', field: :issuer, error_type: :invalid) unless @issuer.start_with?('https://')
          validate_token_endpoint_auth_method!(@token_endpoint_auth_method)
        end

        def validate_entra_id_fields
          if @tenant_id.to_s.empty?
            raise_form_error('Tenant ID is required for Entra ID provider', field: :tenant_id, error_type: :missing)
          end

          # Validate tenant_id is UUID format (shared with the credential probe)
          return if @tenant_id.match?(Onetime::SsoProvider::Entra::TENANT_ID_FORMAT)

          raise_form_error(
            'Tenant ID must be a valid UUID',
            field: :tenant_id,
            error_type: :invalid,
          )
        end

        # ──────────────────────────────────────────────────────────────────────────
        # Provider-specific connection tests
        # ──────────────────────────────────────────────────────────────────────────
        #
        # test_oidc_connection and test_entra_id_connection come from
        # DiscoveryCheck.

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
      end
    end
  end
end
