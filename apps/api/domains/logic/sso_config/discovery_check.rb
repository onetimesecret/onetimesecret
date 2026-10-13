# apps/api/domains/logic/sso_config/discovery_check.rb
#
# frozen_string_literal: true

require 'json'
require_relative '../../../../../lib/onetime/sso_provider/discovery_fetcher'
require_relative '../../../../../lib/onetime/sso_provider/discovery_issuer'
require_relative 'ssrf_protection'
require_relative 'token_endpoint_auth_method_report'

module DomainsAPI
  module Logic
    module SsoConfig
      # The OIDC / Entra ID discovery check shared by TestConnection (form
      # values) and RunDiagnostics (the stored record). Reads @provider_type,
      # @issuer, @tenant_id and @token_endpoint_auth_method from the
      # including logic class and returns the result hash TestConnection
      # has always returned:
      #
      #   { success:, provider_type:, message:, details: { error_code:, ... } }
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
      # The fetcher (Onetime::SsoProvider::DiscoveryFetcher) is the SSRF
      # enforcement point: it resolves + validates the host once via
      # Onetime::Http::Guard and pins every dial to a validated IP. That
      # covers every caller — including test_entra_id_connection, which
      # never passes through valid_issuer_host? (that check remains upstream
      # as a cheap early rejection with a friendly message).
      module DiscoveryCheck
        include SsrfProtection
        include TokenEndpointAuthMethodReport

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

        # details.error_code values that mean the IdP could not be reached,
        # which is not evidence about the configuration.
        UNREACHABLE_ERROR_CODES = %w[timeout connection_failed ssl_error].freeze

        private

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

        def build_discovery_url(issuer)
          Onetime::SsoProvider::DiscoveryFetcher.discovery_url_for(issuer)
        end

        # Fetches through the shared SSRF-safe discovery fetcher and maps its
        # Result onto this endpoint's error_code vocabulary.
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
          OT.le "[#{discovery_log_tag}] Unexpected error testing #{provider_name}: #{error&.class&.name} - #{error&.message}"
          failure(
            "#{provider_name} connection error",
            error_code: 'unexpected_error',
            description: 'An unexpected error occurred. Please try again.',
          )
        end

        def discovery_log_tag
          self.class.name.to_s.split('::').last
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
              **token_endpoint_auth_method_details(discovery),
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
