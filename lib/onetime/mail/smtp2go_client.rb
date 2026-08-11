# lib/onetime/mail/smtp2go_client.rb
#
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Onetime
  module Mail
    # Smtp2goClient - Thin JSON HTTP client for the SMTP2GO v3 API.
    #
    # Shared by the delivery backend (Delivery::Smtp2go) and the sender
    # strategy (SenderStrategies::Smtp2goSenderStrategy) so the HTTP,
    # auth-header, and response-envelope handling live in exactly one
    # place. Named Smtp2goClient (flat) rather than Smtp2go::Client to
    # avoid constant-shadowing with Delivery::Smtp2go.
    #
    # SMTP2GO API conventions (https://developers.smtp2go.com):
    #   - Base URL https://api.smtp2go.com/v3, all endpoints are POST
    #   - Auth via X-Smtp2go-Api-Key header (keys look like api-<32 chars>)
    #   - Every response is wrapped in { "request_id": ..., "data": {...} }
    #   - 200 = success; errors carry data.error_code + data.error
    #
    # Usage:
    #   client = Smtp2goClient.new(api_key: 'api-xxx')
    #   data   = client.post('/email/send', payload)  # => parsed data hash
    #
    class Smtp2goClient
      # Default API base URL. Can be overridden via base_url: or the
      # SMTP2GO_BASE_URL env var (resolved by callers, not here).
      DEFAULT_BASE_URL = 'https://api.smtp2go.com/v3'

      # Structured error for SMTP2GO API failures.
      #
      # Carries the HTTP status, the SMTP2GO error_code (e.g.
      # "E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD"), and a truncated
      # response body for diagnostics. The exception message is the
      # human-readable data.error string when the API provides one.
      class APIError < StandardError
        attr_reader :status_code, :error_code, :response_body

        def initialize(message, status_code:, error_code: nil, response_body: nil)
          super(message)
          @status_code   = status_code
          @error_code    = error_code
          @response_body = response_body
        end
      end

      # @param api_key [String] SMTP2GO API key (format: api-<32 chars>)
      # @param base_url [String, nil] API base URL; nil falls back to DEFAULT_BASE_URL
      # @param open_timeout [Integer] TCP connect timeout in seconds
      # @param read_timeout [Integer] Response read timeout in seconds
      def initialize(api_key:, base_url: DEFAULT_BASE_URL, open_timeout: 15, read_timeout: 30)
        @api_key      = api_key
        @base_url     = (base_url || DEFAULT_BASE_URL).to_s.chomp('/')
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # Makes a POST request and unwraps the SMTP2GO response envelope.
      #
      # Network-level errors (Net::OpenTimeout, SocketError, etc.) are NOT
      # wrapped — they propagate raw so Delivery::Base::NETWORK_ERRORS
      # classification keeps working.
      #
      # @param path [String] API path relative to base URL (e.g. '/email/send')
      # @param payload [Hash] JSON request body
      # @return [Hash] The parsed `data` hash from the response envelope
      # @raise [APIError] On non-2xx responses or unparseable success bodies
      def post(path, payload = {})
        uri  = URI("#{@base_url}#{path}")
        http = build_http_client(uri)

        request                      = Net::HTTP::Post.new(uri)
        request['X-Smtp2go-Api-Key'] = @api_key
        request['Content-Type']      = 'application/json'
        request['Accept']            = 'application/json'
        request.body                 = JSON.generate(payload)

        handle_response(http.request(request))
      end

      private

      # Builds a configured HTTP client (same knobs as SendGridSenderStrategy).
      #
      # @param uri [URI] Request URI
      # @return [Net::HTTP]
      def build_http_client(uri)
        http              = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == 'https'
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        http
      end

      # Parses the response envelope and raises APIError on failure.
      #
      # @param response [Net::HTTPResponse]
      # @return [Hash] The `data` hash on success
      # @raise [APIError]
      def handle_response(response)
        code = response.code.to_i
        body = response.body.to_s
        data = parse_data(body)

        if code.between?(200, 299)
          if data.nil?
            raise APIError.new(
              "Invalid JSON response from SMTP2GO: #{body[0, 200]}",
              status_code: code,
              response_body: body[0, 500],
            )
          end

          # SMTP2GO can carry an error envelope inside a 2xx response;
          # treat data.error/error_code as a failure so callers never
          # mistake it for success data.
          if data['error'] || data['error_code']
            raise APIError.new(
              data['error'] || "HTTP #{code}",
              status_code: code,
              error_code: data['error_code'],
              response_body: body[0, 500],
            )
          end

          return data
        end

        error_code = data&.dig('error_code') if data.is_a?(Hash)
        message    = (data.is_a?(Hash) && data['error']) || "HTTP #{code}"
        raise APIError.new(
          message,
          status_code: code,
          error_code: error_code,
          response_body: body[0, 500],
        )
      end

      # Extracts the `data` hash from the response envelope, tolerating
      # non-JSON bodies (returns nil) and envelopes without a data key
      # (returns an empty hash so callers can dig safely).
      #
      # @param body [String] Raw response body
      # @return [Hash, nil] Parsed data hash, or nil when body is not JSON
      def parse_data(body)
        return {} if body.empty?

        parsed = JSON.parse(body)
        return {} unless parsed.is_a?(Hash)

        data = parsed['data']
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        nil
      end
    end
  end
end
