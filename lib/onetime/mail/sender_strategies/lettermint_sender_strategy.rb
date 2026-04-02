# lib/onetime/mail/sender_strategies/lettermint_sender_strategy.rb
#
# frozen_string_literal: true

require_relative 'base_sender_strategy'

module Onetime
  module Mail
    module SenderStrategies
      # LettermintSenderStrategy - Lettermint sender domain provisioning.
      #
      # Provisions sender authentication through Lettermint's Domain API.
      #
      # Lettermint provides DKIM configuration via selector-based CNAME records
      # and SPF TXT records that must be added to the domain's DNS.
      #
      # Example DNS records for domain "example.com":
      #   lm1._domainkey.example.com CNAME lm1.dkim.lettermint.co
      #   lm2._domainkey.example.com CNAME lm2.dkim.lettermint.co
      #   example.com TXT "v=spf1 include:lettermint.co ~all"
      #
      # Lettermint has TWO separate APIs:
      #   1. Sending API - uses x-lettermint-token header (project token)
      #   2. Team API    - uses Authorization: Bearer header (team token)
      #
      # Domain provisioning uses the Team API:
      #   - POST   /domains              Create domain, returns DNS records
      #   - GET    /domains/:id          Get domain status and records
      #   - DELETE /domains/:id          Remove domain
      #   - POST   /domains/:id/dns-records/verify  Verify DNS records
      #
      # Configuration:
      #   team_token: Lettermint Team API token (for domain provisioning)
      #   api_token:  Lettermint Sending API token (for email delivery)
      #   base_url:   Custom API base URL (optional, default: https://api.lettermint.co/v1)
      #
      class LettermintSenderStrategy < BaseSenderStrategy
        # Default API base URL for Team API. Can be overridden via credentials[:base_url]
        # or EMAIL_PROVIDERS_LETTERMINT_API_BASE_URL env var (loaded via ProviderConfig).
        DEFAULT_BASE_URL = 'https://api.lettermint.co/v1'

        # Provisions sender DNS records through Lettermint's Domain API.
        #
        # Creates a new domain entry and returns the DNS records that must
        # be configured for DKIM and SPF authentication.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include :api_token; optionally :base_url
        # @return [Hash] Provisioning result:
        #   - :success [Boolean]
        #   - :message [String]
        #   - :dns_records [Array<Hash>] Formatted DNS records
        #   - :provider_data [Hash] Lettermint-specific data (status, created_at, etc.)
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

          team_token = credentials[:team_token] || credentials['team_token']
          unless team_token && !team_token.empty?
            return {
              success: false,
              message: 'Lettermint Team API token is required for domain provisioning',
              dns_records: [],
              error: 'missing_team_token',
            }
          end

          log_info "[lettermint-sender] Provisioning sender domain for #{domain}"

          client   = build_client(credentials)
          response = create_or_get_domain(client, domain)

          # Lettermint returns: { domain:, status:, dns_records: [...], created_at: }
          dns_records = normalize_dns_records(response['dns_records'] || [])

          {
            success: true,
            message: "Domain #{domain} provisioned with Lettermint",
            dns_records: dns_records,
            identity_id: response['domain'],
            provider_data: {
              status: response['status'],
              created_at: response['created_at'],
              domain: response['domain'],
            },
          }
        rescue Lettermint::ValidationError => ex
          log_error "[lettermint-sender] Validation error for #{domain}: #{ex.message}"
          {
            success: false,
            message: "Validation error: #{ex.message}",
            dns_records: [],
            error: 'validation_error',
          }
        rescue Lettermint::AuthenticationError => ex
          log_error "[lettermint-sender] Authentication failed: #{ex.message}"
          {
            success: false,
            message: "Authentication failed: #{ex.message}",
            dns_records: [],
            error: 'authentication_error',
          }
        rescue Lettermint::RateLimitError => ex
          log_error "[lettermint-sender] Rate limited: #{ex.message}"
          {
            success: false,
            message: "Rate limited by Lettermint API: #{ex.message}",
            dns_records: [],
            error: 'rate_limited',
          }
        rescue Lettermint::TimeoutError => ex
          log_error "[lettermint-sender] Request timed out: #{ex.message}"
          {
            success: false,
            message: "Lettermint API timed out: #{ex.message}",
            dns_records: [],
            error: 'timeout',
          }
        rescue Lettermint::HttpRequestError => ex
          log_error "[lettermint-sender] Provisioning failed for #{domain}: #{ex.message}"
          {
            success: false,
            message: "Lettermint API error: #{ex.message}",
            dns_records: [],
            error: "http_#{ex.status_code}",
          }
        rescue StandardError => ex
          log_error "[lettermint-sender] Provisioning failed: #{ex.message}"
          {
            success: false,
            message: "Provisioning failed: #{ex.message}",
            dns_records: [],
            error: ex.message,
          }
        end

        # Checks verification status of a sender domain.
        #
        # Queries Lettermint Team API for the domain's current verification state.
        # Uses filter to find domain by name, then fetches details with DNS records.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include :team_token
        # @return [Hash] Verification status:
        #   - :verified [Boolean]
        #   - :status [String] 'verified', 'pending', 'not_found', 'error'
        #   - :message [String]
        #   - :details [Hash, nil] Additional verification details
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

          team_token = credentials[:team_token] || credentials['team_token']
          unless team_token && !team_token.empty?
            return {
              verified: false,
              status: 'error',
              message: 'Lettermint Team API token is required',
            }
          end

          log_info "[lettermint-sender] Checking verification status for #{domain}"

          client = build_client(credentials)

          # Find domain by name to get its ID
          list         = client.get(path: "/domains?filter[domain]=#{domain}")
          domain_entry = list['data']&.first

          unless domain_entry
            return {
              verified: false,
              status: 'not_found',
              message: "Domain #{domain} not found in Lettermint",
            }
          end

          # Fetch full details with DNS records
          response = client.get(path: "/domains/#{domain_entry['id']}?include=dnsRecords")

          # Status enum: verified, partially_verified, pending_verification, failed_verification
          status   = response['status'] || domain_entry['status'] || 'unknown'
          verified = status == 'verified'

          {
            verified: verified,
            status: status.downcase.tr('_', '-'),
            message: verification_message(domain, verified, status),
            details: {
              dns_records: normalize_dns_records(response['dns_records'] || []),
              domain: response['domain'],
              domain_id: response['id'],
            },
          }
        rescue Lettermint::HttpRequestError => ex
          log_error "[lettermint-sender] Verification check failed for #{domain}: #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "Verification check failed: #{ex.message}",
          }
        rescue StandardError => ex
          log_error "[lettermint-sender] Verification check failed: #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "Verification check failed: #{ex.message}",
          }
        end

        # Deletes a sender domain from Lettermint.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include :team_token
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

          team_token = credentials[:team_token] || credentials['team_token']
          unless team_token && !team_token.empty?
            return {
              deleted: false,
              message: 'Lettermint Team API token is required',
            }
          end

          log_info "[lettermint-sender] Deleting sender domain for #{domain}"

          client = build_client(credentials)

          # Find domain by name to get its ID
          list         = client.get(path: "/domains?filter[domain]=#{domain}")
          domain_entry = list['data']&.first

          unless domain_entry
            # Domain doesn't exist - treat as successful deletion
            return {
              deleted: true,
              message: "Domain #{domain} was already deleted or never existed",
            }
          end

          client.delete(path: "/domains/#{domain_entry['id']}")

          {
            deleted: true,
            message: "Domain #{domain} removed from Lettermint",
          }
        rescue Lettermint::HttpRequestError => ex
          if ex.status_code == 404
            # Domain doesn't exist - treat as successful deletion
            {
              deleted: true,
              message: "Domain #{domain} was already deleted or never existed",
            }
          else
            log_error "[lettermint-sender] Deletion failed for #{domain}: #{ex.message}"
            {
              deleted: false,
              message: "Deletion failed: #{ex.message}",
            }
          end
        rescue StandardError => ex
          log_error "[lettermint-sender] Deletion failed: #{ex.message}"
          {
            deleted: false,
            message: "Deletion failed: #{ex.message}",
          }
        end

        protected

        def validate_config!
          # Validation happens at call time with provided credentials
        end

        private

        # Build Team API HTTP client from credentials.
        #
        # Domain provisioning uses the Team API with Bearer auth, NOT the
        # Sending API (x-lettermint-token). The Lettermint gem's HttpClient
        # is for the Sending API, so we use Faraday directly here.
        #
        # @param credentials [Hash] Must include :team_token, optionally :base_url
        # @return [TeamApiClient] Simple wrapper around Faraday
        #
        def build_client(credentials)
          team_token = credentials[:team_token] || credentials['team_token']
          base_url   = credentials[:base_url] || credentials['base_url'] || DEFAULT_BASE_URL
          timeout    = credentials[:timeout] || credentials['timeout'] || 30

          TeamApiClient.new(team_token: team_token, base_url: base_url, timeout: timeout)
        end

        # Simple HTTP client for Lettermint Team API (Bearer auth).
        class TeamApiClient
          def initialize(team_token:, base_url:, timeout:)
            require 'faraday'
            @connection = Faraday.new(url: "#{base_url.chomp('/')}/") do |f|
              f.request :json
              f.response :json
              f.options.timeout      = timeout
              f.options.open_timeout = timeout
              f.headers              = {
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
                'Authorization' => "Bearer #{team_token}",
                'User-Agent' => 'OnetimeSecret/LettermintSenderStrategy',
              }
            end
          end

          def get(path:)
            response = @connection.get(path.delete_prefix('/'))
            handle_response(response)
          end

          def post(path:, data: nil)
            response = @connection.post(path.delete_prefix('/')) { |req| req.body = data }
            handle_response(response)
          end

          def delete(path:)
            response = @connection.delete(path.delete_prefix('/'))
            handle_response(response)
          end

          private

          def handle_response(response)
            return response.body if response.success?

            raise_api_error(response.status, response.body)
          end

          def raise_api_error(status, body)
            require 'lettermint'
            msg = body.is_a?(Hash) ? (body['message'] || body['error'] || "HTTP #{status}") : "HTTP #{status}"
            raise Lettermint::HttpRequestError.new(message: msg, status_code: status, response_body: body)
          end
        end

        # Creates a new domain or retrieves existing one on 409 conflict.
        #
        # POST /domains returns: { id, domain, status, dns_records[], ... }
        # GET /domains/{id}?include=dnsRecords returns domain with DNS records
        #
        # @param client [TeamApiClient]
        # @param domain [String] Domain name (e.g., "example.com")
        # @return [Hash] Parsed API response with id, domain, status, dns_records
        #
        def create_or_get_domain(client, domain)
          response  = client.post(path: '/domains', data: { domain: domain })
          domain_id = response['id']

          # Fetch full details with DNS records
          client.get(path: "/domains/#{domain_id}?include=dnsRecords")
        rescue Lettermint::HttpRequestError => ex
          raise unless ex.status_code == 409

          # Domain already exists - find it in the list and retrieve
          log_info "[lettermint-sender] Domain #{domain} already exists, retrieving..."
          list     = client.get(path: "/domains?filter[domain]=#{domain}")
          existing = list['data']&.first
          raise Lettermint::HttpRequestError.new(message: "Domain #{domain} not found", status_code: 404) unless existing

          client.get(path: "/domains/#{existing['id']}?include=dnsRecords")
        end

        # Normalize Lettermint DNS records to standard format.
        #
        # Lettermint returns records as:
        #   [{ "type": "CNAME", "name": "lm1._domainkey.example.com", "value": "lm1.dkim.lettermint.co" }, ...]
        #
        # Normalized to consistent shape matching SES/SendGrid:
        #   [{ type: 'CNAME', name: '...', value: '...' }, ...]
        #
        # Returns Array<Hash> with {type:, name:, value:} entries, matching
        # the shape used by SES and SendGrid strategies.
        #
        # @param records [Array<Hash>] Raw DNS records from Lettermint
        # @return [Array<Hash>] Normalized records with symbolized keys
        #
        def normalize_dns_records(records)
          return [] if records.nil? || records.empty?

          records.filter_map do |record|
            next unless record.is_a?(Hash)

            rec_type = record['type'] || record[:type]
            rec_name = record['name'] || record[:name]
            rec_val  = record['value'] || record[:value]

            next unless rec_type && rec_name && rec_val

            {
              type: rec_type.upcase,
              name: rec_name,
              value: rec_val,
            }
          end
        end

        # Maps verification state to human-readable message.
        #
        # @param domain [String] Domain name
        # @param verified [Boolean] Verification state
        # @param status [String] Provider status string
        # @return [String]
        #
        def verification_message(domain, verified, status)
          if verified
            "Domain #{domain} is verified and ready for sending"
          else
            case status.to_s.downcase
            when 'pending'
              "Domain #{domain} pending verification - DNS records found, awaiting propagation"
            when 'failed'
              "Domain #{domain} verification failed - check DNS records are correctly configured"
            else
              "Domain #{domain} pending verification"
            end
          end
        end
      end
    end
  end
end
