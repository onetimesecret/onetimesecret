# lib/onetime/mail/sender_strategies/sendgrid_sender_strategy.rb
#
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'base_sender_strategy'

module Onetime
  module Mail
    module SenderStrategies
      # SendGridSenderStrategy - SendGrid sender domain provisioning.
      #
      # Provisions sender authentication through SendGrid's Domain
      # Authentication API (formerly "whitelabeling").
      #
      # SendGrid provides several DNS records including:
      #   - CNAME for branded links (em1234.example.com)
      #   - CNAME for DKIM signing (s1._domainkey.example.com)
      #   - TXT for SPF (if using subdomain)
      #
      # Configuration:
      #   api_key: SendGrid API key with domain authentication permissions
      #
      # API Reference:
      #   https://docs.sendgrid.com/api-reference/domain-authentication
      #
      class SendGridSenderStrategy < BaseSenderStrategy
        API_BASE_URI          = 'https://api.sendgrid.com/v3'
        DOMAIN_LIST_PAGE_SIZE = 50

        # Structured error for SendGrid API failures
        class APIError < StandardError
          attr_reader :status_code, :response_body

          def initialize(message, status_code:, response_body: nil)
            super(message)
            @status_code   = status_code
            @response_body = response_body
          end
        end

        # Provisions domain authentication via SendGrid API.
        #
        # Creates a new domain authentication entry and returns the DNS
        # records that must be configured for DKIM and branded links.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include :api_key
        # @return [Hash] Provisioning result:
        #   - :success [Boolean]
        #   - :message [String]
        #   - :dns_records [Array<Hash>] Formatted DNS records
        #   - :provider_data [Hash] SendGrid-specific data (domain_id, subdomain, etc.)
        #   - :error [String, nil] Error message if failed
        #
        def provision_dns_records(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              success: false,
              message: 'Invalid from_address: cannot extract domain',
              dns_records: [],
              error: 'invalid_from_address',
            }
          end

          api_key = credentials[:api_key]
          unless api_key && !api_key.empty?
            return {
              success: false,
              message: 'SendGrid API key is required',
              dns_records: [],
              error: 'missing_api_key',
            }
          end

          log_info "[sendgrid-sender] Provisioning sender authentication for #{domain}"

          response = post_request(
            '/whitelabel/domains',
            { domain: domain, automatic_security: true },
            api_key: api_key,
          )

          if response[:success]
            data        = response[:data]
            dns_records = build_dns_records(data)

            {
              success: true,
              message: "Domain authentication created for #{domain}",
              dns_records: dns_records,
              provider_data: {
                domain_id: data['id'],
                subdomain: data['subdomain'],
                dns: data['dns'],
                valid: data['valid'],
              },
            }
          else
            {
              success: false,
              message: response[:error] || 'SendGrid API error',
              dns_records: [],
              error: response[:error],
            }
          end
        rescue StandardError => ex
          log_error "[sendgrid-sender] Provisioning failed: #{ex.message}"
          {
            success: false,
            message: "Provisioning failed: #{ex.message}",
            dns_records: [],
            error: ex.message,
          }
        end

        # Checks verification status of domain authentication.
        #
        # Queries SendGrid to find the domain and triggers validation.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include :api_key; optionally :domain_id
        # @return [Hash] Verification status:
        #   - :verified [Boolean]
        #   - :status [String] 'verified', 'pending', 'failed', 'not_found'
        #   - :message [String]
        #   - :details [Hash, nil] Per-record validation results
        #
        def check_verification_status(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              verified: false,
              status: 'invalid',
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          api_key = credentials[:api_key]
          unless api_key && !api_key.empty?
            return {
              verified: false,
              status: 'error',
              message: 'SendGrid API key is required',
            }
          end

          log_info "[sendgrid-sender] Checking verification status for #{domain}"

          # First, find the domain ID if not provided
          domain_id = credentials[:domain_id] || find_domain_id(domain, api_key: api_key)

          unless domain_id
            return {
              verified: false,
              status: 'not_found',
              message: "Domain authentication not found for #{domain}",
            }
          end

          # Trigger validation check
          response = post_request(
            "/whitelabel/domains/#{domain_id}/validate",
            {},
            api_key: api_key,
          )

          if response[:success]
            data      = response[:data]
            all_valid = data['valid'] == true ||
                        (data['validation_results'] && all_records_valid?(data['validation_results']))

            {
              verified: all_valid,
              status: all_valid ? 'verified' : 'pending',
              message: all_valid ? "Domain #{domain} is verified" : 'DNS records pending verification',
              details: data['validation_results'],
            }
          else
            {
              verified: false,
              status: 'error',
              message: response[:error] || 'Validation check failed',
            }
          end
        rescue StandardError => ex
          log_error "[sendgrid-sender] Verification check failed: #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "Verification check failed: #{ex.message}",
          }
        end

        # Deletes domain authentication from SendGrid.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include :api_key; optionally :domain_id
        # @return [Hash] Deletion result:
        #   - :deleted [Boolean]
        #   - :message [String]
        #
        def delete_sender_identity(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              deleted: false,
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          api_key = credentials[:api_key]
          unless api_key && !api_key.empty?
            return {
              deleted: false,
              message: 'SendGrid API key is required',
            }
          end

          log_info "[sendgrid-sender] Deleting sender authentication for #{domain}"

          # Find the domain ID if not provided
          domain_id = credentials[:domain_id] || find_domain_id(domain, api_key: api_key)

          unless domain_id
            return {
              deleted: false,
              message: "Domain authentication not found for #{domain}",
            }
          end

          response = delete_request(
            "/whitelabel/domains/#{domain_id}",
            api_key: api_key,
          )

          if response[:success]
            {
              deleted: true,
              message: "Domain authentication deleted for #{domain}",
            }
          else
            {
              deleted: false,
              message: response[:error] || 'Delete failed',
            }
          end
        rescue StandardError => ex
          log_error "[sendgrid-sender] Delete failed: #{ex.message}"
          {
            deleted: false,
            message: "Delete failed: #{ex.message}",
          }
        end

        protected

        def validate_config!
          # Validation happens at call time with provided credentials
        end

        private

        # Converts SendGrid DNS response to standardized format.
        #
        # SendGrid returns DNS records in this structure:
        #   {
        #     "dns": {
        #       "mail_cname": { "host": "...", "type": "cname", "data": "..." },
        #       "dkim1": { "host": "...", "type": "cname", "data": "..." },
        #       "dkim2": { "host": "...", "type": "cname", "data": "..." }
        #     }
        #   }
        #
        # @param data [Hash] SendGrid API response
        # @return [Array<Hash>] Standardized DNS records
        #
        def build_dns_records(data)
          dns     = data['dns'] || {}
          records = []

          dns.each do |key, record|
            next unless record.is_a?(Hash)

            records << {
              type: (record['type'] || 'CNAME').upcase,
              name: record['host'],
              value: record['data'],
              purpose: key, # e.g., 'mail_cname', 'dkim1', 'dkim2'
            }
          end

          records
        end

        # Checks if all validation results indicate success.
        #
        # @param validation_results [Hash] Per-record validation data
        # @return [Boolean]
        #
        def all_records_valid?(validation_results)
          return false unless validation_results.is_a?(Hash)

          validation_results.values.all? do |result|
            result.is_a?(Hash) && result['valid'] == true
          end
        end

        # Finds domain authentication ID by domain name.
        #
        # Paginates through SendGrid's domain authentication list using
        # limit/offset, since the default response is capped at ~50 domains.
        #
        # @param domain [String] Domain to search for
        # @param api_key [String] SendGrid API key
        # @return [Integer, nil] Domain ID or nil if not found
        #
        def find_domain_id(domain, api_key:)
          limit  = DOMAIN_LIST_PAGE_SIZE
          offset = 0

          loop do
            response = get_request(
              "/whitelabel/domains?limit=#{limit}&offset=#{offset}",
              api_key: api_key,
            )
            return nil unless response[:success]

            domains = response[:data]
            return nil unless domains.is_a?(Array)

            match = domains.find { |d| d['domain'] == domain }
            return match['id'] if match

            # Stop when fewer results than the limit — we've seen all pages
            break if domains.size < limit

            offset += limit
          end

          nil
        end

        # Makes a GET request to SendGrid API.
        #
        # @param path [String] API path (without base URI)
        # @param api_key [String] SendGrid API key
        # @return [Hash] { success: Boolean, data: Hash/Array, error: String }
        #
        def get_request(path, api_key:)
          uri  = URI("#{API_BASE_URI}#{path}")
          http = build_http_client(uri)

          request                  = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{api_key}"
          request['Content-Type']  = 'application/json'

          execute_request(http, request)
        end

        # Makes a POST request to SendGrid API.
        #
        # @param path [String] API path (without base URI)
        # @param body [Hash] Request body
        # @param api_key [String] SendGrid API key
        # @return [Hash] { success: Boolean, data: Hash, error: String }
        #
        def post_request(path, body, api_key:)
          uri  = URI("#{API_BASE_URI}#{path}")
          http = build_http_client(uri)

          request                  = Net::HTTP::Post.new(uri)
          request['Authorization'] = "Bearer #{api_key}"
          request['Content-Type']  = 'application/json'
          request.body             = body.to_json

          execute_request(http, request)
        end

        # Makes a DELETE request to SendGrid API.
        #
        # @param path [String] API path (without base URI)
        # @param api_key [String] SendGrid API key
        # @return [Hash] { success: Boolean, data: Hash, error: String }
        #
        def delete_request(path, api_key:)
          uri  = URI("#{API_BASE_URI}#{path}")
          http = build_http_client(uri)

          request                  = Net::HTTP::Delete.new(uri)
          request['Authorization'] = "Bearer #{api_key}"
          request['Content-Type']  = 'application/json'

          execute_request(http, request)
        end

        # Builds configured HTTP client.
        #
        # @param uri [URI] Request URI
        # @return [Net::HTTP]
        #
        def build_http_client(uri)
          http              = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.open_timeout = 15
          http.read_timeout = 30
          http
        end

        # Executes HTTP request and parses response.
        #
        # @param http [Net::HTTP] HTTP client
        # @param request [Net::HTTPRequest] Request to execute
        # @return [Hash] { success: Boolean, data: Hash/Array, error: String }
        #
        def execute_request(http, request)
          response = http.request(request)
          code     = response.code.to_i
          body     = response.body.to_s

          # Parse JSON response (handle empty body for DELETE)
          data = body.empty? ? {} : JSON.parse(body)

          if code.between?(200, 299)
            { success: true, data: data }
          else
            error_message = extract_error_message(data) || "HTTP #{code}"
            { success: false, data: data, error: error_message }
          end
        rescue JSON::ParserError
          { success: false, data: {}, error: "Invalid JSON response: #{body[0, 200]}" }
        end

        # Extracts error message from SendGrid error response.
        #
        # @param data [Hash] Parsed response body
        # @return [String, nil]
        #
        def extract_error_message(data)
          return nil unless data.is_a?(Hash)

          # SendGrid error format: { "errors": [{ "message": "..." }] }
          if data['errors'].is_a?(Array) && data['errors'].first
            data['errors'].first['message']
          elsif data['error']
            data['error']
          end
        end
      end
    end
  end
end
