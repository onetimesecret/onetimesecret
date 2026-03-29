# apps/api/domains/logic/sso_config/test_connection.rb
#
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'timeout'
require_relative 'base'
require_relative 'ssrf_protection'

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
      # Request body:
      # - provider_type: Required. One of: oidc, entra_id, google, github
      # - client_id: Required. OAuth client ID
      # - tenant_id: Required for entra_id provider
      # - issuer: Required for oidc provider (HTTPS URL)
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

        # Connection timeout in seconds
        CONNECTION_TIMEOUT = 10

        # Read timeout in seconds
        READ_TIMEOUT = 10

        # Required fields in OIDC discovery document
        REQUIRED_OIDC_FIELDS = %w[
          authorization_endpoint
          token_endpoint
          jwks_uri
          issuer
        ].freeze

        VALID_PROVIDER_TYPES = Onetime::DomainSsoConfig::PROVIDER_TYPES.freeze

        def process_params
          @domain_id     = sanitize_identifier(params['extid'])
          @provider_type = sanitize_plain_text(params['provider_type'])
          @client_id     = params['client_id'].to_s.strip
          @tenant_id     = sanitize_plain_text(params['tenant_id'])
          @issuer        = sanitize_url(params['issuer'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Validate provider_type
          validate_provider_type

          # Validate client_id (required for all providers)
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
                   when 'google'
                     test_google_connection
                   when 'github'
                     test_github_connection
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
          raise_form_error('Client ID is required', field: :client_id, error_type: :missing) if @client_id.to_s.empty?
        end

        def validate_provider_specific_fields
          case @provider_type
          when 'oidc'
            validate_oidc_fields
          when 'entra_id'
            validate_entra_id_fields
          when 'google'
            validate_google_fields
          when 'github'
            validate_github_fields
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

        def validate_google_fields
          # Google client_id format: ends with .apps.googleusercontent.com
          return if @client_id.end_with?('.apps.googleusercontent.com')

          raise_form_error(
            'Google Client ID must end with .apps.googleusercontent.com',
            field: :client_id,
            error_type: :invalid,
          )
        end

        def validate_github_fields
          # GitHub client_id format: "Iv1." prefix followed by hex characters
          # Example: Iv1.8a61f9b3a7aba766
          return if @client_id.match?(/\AIv1\.[0-9a-f]{10,40}\z/i)

          raise_form_error(
            'GitHub Client ID must be in format Iv1.{hex} (e.g., Iv1.8a61f9b3a7aba766)',
            field: :client_id,
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

        def test_google_connection
          discovery_url = 'https://accounts.google.com/.well-known/openid-configuration'
          fetch_and_validate_discovery(discovery_url, 'Google')
        end

        def test_github_connection
          # GitHub doesn't have OIDC discovery - just validate format
          # The client_id format was already validated in validate_github_fields
          {
            success: true,
            provider_type: @provider_type,
            message: 'GitHub credentials format validated',
            details: {
              client_id_format: 'valid',
              note: 'GitHub does not support OIDC discovery. Credentials will be validated during authentication.',
            },
          }
        end

        # ──────────────────────────────────────────────────────────────────────────
        # Discovery document handling
        # ──────────────────────────────────────────────────────────────────────────

        def build_discovery_url(issuer)
          # Normalize issuer URL
          base = issuer.to_s.chomp('/')
          "#{base}/.well-known/openid-configuration"
        end

        def fetch_and_validate_discovery(url, provider_name)
          response = fetch_url(url)

          case response
          when Net::HTTPSuccess
            validate_discovery_response(response, provider_name)
          when Net::HTTPNotFound
            {
              success: false,
              provider_type: @provider_type,
              message: "#{provider_name} discovery document not found",
              details: {
                error_code: 'discovery_not_found',
                http_status: response.code.to_i,
                url: url,
              },
            }
          else
            {
              success: false,
              provider_type: @provider_type,
              message: "#{provider_name} discovery request failed",
              details: {
                error_code: 'http_error',
                http_status: response.code.to_i,
                description: response.message,
              },
            }
          end
        rescue Timeout::Error
          {
            success: false,
            provider_type: @provider_type,
            message: "#{provider_name} connection timed out",
            details: {
              error_code: 'timeout',
              timeout_seconds: CONNECTION_TIMEOUT,
              url: url,
            },
          }
        rescue OpenSSL::SSL::SSLError => ex
          {
            success: false,
            provider_type: @provider_type,
            message: "#{provider_name} SSL/TLS error",
            details: {
              error_code: 'ssl_error',
              description: sanitize_error_message(ex.message),
            },
          }
        rescue SocketError => ex
          {
            success: false,
            provider_type: @provider_type,
            message: "#{provider_name} connection failed",
            details: {
              error_code: 'connection_failed',
              description: sanitize_error_message(ex.message),
            },
          }
        rescue StandardError => ex
          OT.le "[TestConnection] Unexpected error testing #{provider_name}: #{ex.class.name} - #{ex.message}"
          {
            success: false,
            provider_type: @provider_type,
            message: "#{provider_name} connection error",
            details: {
              error_code: 'unexpected_error',
              description: 'An unexpected error occurred. Please try again.',
            },
          }
        end

        def fetch_url(url)
          uri = URI.parse(url)

          http              = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = (uri.scheme == 'https')
          http.open_timeout = CONNECTION_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.verify_mode  = OpenSSL::SSL::VERIFY_PEER

          request               = Net::HTTP::Get.new(uri.request_uri)
          request['Accept']     = 'application/json'
          request['User-Agent'] = 'OneTimeSecret-SSO-Test/1.0'

          http.request(request)
        end

        def validate_discovery_response(response, provider_name)
          # Parse JSON
          discovery = JSON.parse(response.body)

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
              content_type: response['Content-Type'],
            },
          }
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
