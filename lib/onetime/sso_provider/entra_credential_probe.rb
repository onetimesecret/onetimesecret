# lib/onetime/sso_provider/entra_credential_probe.rb
#
# frozen_string_literal: true

require 'oauth2'
require_relative 'entra'

module Onetime
  module SsoProvider
    # One client-credentials token request against an Entra tenant, to learn
    # whether the tenant accepts a stored client_id / client_secret pair.
    #
    # What a result means (docs/runbooks/sso-credential-health.md, "A
    # client-credentials request is not an SSO test"): :passed says the
    # secret was accepted for THIS request and nothing more; it does not
    # exercise redirect URIs, user assignment, Conditional Access or claims.
    # AADSTS7000215 and AADSTS7000222 are about the secret. Any other AADSTS
    # code says nothing about the secret and is reported :inconclusive.
    #
    # Transport: the request is built the way omniauth-entra-id builds its
    # own (OmniAuth::Strategies::EntraId#client — an OAuth2::Client with
    # site https://login.microsoftonline.com and token_url
    # "<tenant_id>/oauth2/v2.0/token"), with the SAME auth_scheme the tenant
    # builder emits (CustomDomain::SsoConfig#build_entra_id_options,
    # client_options.auth_scheme = :request_body, #4764). AUTH_SCHEME is
    # pinned against that builder in spec so the two cannot drift. The
    # OmniAuth strategy itself is not instantiated: it needs a Rack request.
    #
    # SSRF: the host is the constant SITE and the only interpolated value is
    # tenant_id, which must match Entra::TENANT_ID_FORMAT before a URL is
    # built, so the egress guard (Onetime::Http::Guard) is not consulted.
    #
    # Never exposes the secret, the token, or Entra's error_description
    # (it carries correlation ids and the app id): the Result carries a
    # status, an error_code, the HTTP status and the bare AADSTS code.
    class EntraCredentialProbe
      SITE         = 'https://login.microsoftonline.com'
      SCOPE        = 'https://graph.microsoft.com/.default'
      AUTH_SCHEME  = :request_body
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 10

      # AADSTS codes that are evidence about the secret itself.
      SECRET_ERROR_CODES = {
        'AADSTS7000215' => 'invalid_client_secret',
        'AADSTS7000222' => 'client_secret_expired',
        'AADSTS700016' => 'app_not_found_in_tenant',
      }.freeze

      AADSTS_PATTERN = /AADSTS\d+/

      Result = Data.define(:status, :error_code, :http_status, :aadsts_code) do
        def passed?
          status == :passed
        end
      end

      # @param tenant_id [String]
      # @param client_id [String]
      # @param client_secret [String]
      # @return [Result]
      def self.call(tenant_id:, client_id:, client_secret:)
        new(tenant_id: tenant_id, client_id: client_id, client_secret: client_secret).call
      end

      def initialize(tenant_id:, client_id:, client_secret:)
        @tenant_id     = tenant_id.to_s
        @client_id     = client_id.to_s
        @client_secret = client_secret.to_s
      end

      # @return [Result]
      def call
        return Result.new(status: :failed, error_code: 'invalid_tenant_id', http_status: nil, aadsts_code: nil) unless Onetime::SsoProvider::Entra::TENANT_ID_FORMAT.match?(@tenant_id)

        token = client.client_credentials.get_token('scope' => SCOPE)
        return result(:inconclusive, 'invalid_response', http_status: 200) if token.token.to_s.empty?

        result(:passed, nil, http_status: 200)
      rescue OAuth2::Error => ex
        # ex.message embeds error_description; only the response is read.
        classify_error_response(ex.response)
      rescue Faraday::TimeoutError
        result(:inconclusive, 'timeout')
      rescue Faraday::SSLError
        result(:inconclusive, 'ssl_error')
      rescue Faraday::ConnectionFailed => ex
        # faraday-net_http reports an OPEN timeout (Net::OpenTimeout) as
        # ConnectionFailed and only a read timeout as TimeoutError; oauth2
        # then re-raises it as OAuth2::ConnectionError with the message only,
        # so the original is reached through #cause, not #wrapped_exception.
        result(:inconclusive, timeout_cause?(ex) ? 'timeout' : 'connection_failed')
      rescue StandardError => ex
        # Class name only: the message may quote the request or the response.
        OT.le "[EntraCredentialProbe] Unexpected #{ex.class.name} during token request"
        result(:inconclusive, 'unexpected_error')
      end

      private

      # @param error [Exception]
      # @return [Boolean] whether a Timeout::Error sits anywhere in the chain
      def timeout_cause?(error)
        current = error
        while current
          return true if current.is_a?(Timeout::Error)

          wrapped = current.respond_to?(:wrapped_exception) ? current.wrapped_exception : nil
          return true if wrapped.is_a?(Timeout::Error)

          current = current.cause
        end
        false
      end

      def client
        OAuth2::Client.new(
          @client_id,
          @client_secret,
          site: SITE,
          token_url: "#{@tenant_id}/oauth2/v2.0/token",
          auth_scheme: AUTH_SCHEME,
          raise_errors: true,
          max_redirects: 0,
          connection_opts: { request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT } },
        )
      end

      # @param response [OAuth2::Response, Hash, Object] OAuth2::Error#response:
      #   an OAuth2::Response for an HTTP error, a Hash when the gem refused a
      #   2xx body with no token.
      def classify_error_response(response)
        return result(:inconclusive, 'invalid_response') unless response.respond_to?(:status) && response.respond_to?(:parsed)

        http_status = response.status
        parsed      = begin
          response.parsed
        rescue StandardError
          nil
        end
        return result(:inconclusive, 'invalid_response', http_status: http_status) unless parsed.is_a?(Hash)

        aadsts = parsed['error_description'].to_s[AADSTS_PATTERN]
        return result(:inconclusive, 'invalid_response', http_status: http_status) if aadsts.nil?

        error_code = SECRET_ERROR_CODES[aadsts]
        if error_code
          result(:failed, error_code, http_status: http_status, aadsts_code: aadsts)
        else
          result(:inconclusive, 'provider_error', http_status: http_status, aadsts_code: aadsts)
        end
      end

      def result(status, error_code, http_status: nil, aadsts_code: nil)
        Result.new(status: status, error_code: error_code, http_status: http_status, aadsts_code: aadsts_code)
      end
    end
  end
end
