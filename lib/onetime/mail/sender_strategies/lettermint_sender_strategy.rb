# lib/onetime/mail/sender_strategies/lettermint_sender_strategy.rb
#
# frozen_string_literal: true

require_relative 'base_sender_strategy'

module Onetime
  module Mail
    module SenderStrategies
      # LettermintSenderStrategy - Lettermint sender domain provisioning and provider checks.
      #
      # This class handles PROVISIONING (create domain, get DNS records) and
      # PROVIDER-LEVEL verification (ask Lettermint API if domain is verified).
      #
      # For DNS-LEVEL verification (lookup DNS records, compare expected vs actual),
      # see DomainValidation::SenderStrategies::LettermintValidation instead.
      #
      # Used by:
      #   - ProvisionSenderDomain operation (provisioning)
      #   - DomainValidationWorker (provider check only, via check_provider_verification_status)
      #   - DnsRecordCheckWorker (fact-finding, via inherited check_dns_records)
      #
      # Provisions sender authentication through Lettermint's Domain API.
      #
      # Lettermint provides DKIM configuration via selector-based CNAME records
      # and SPF via a Return-Path CNAME record (no direct SPF TXT record needed).
      #
      # Example DNS records for domain "example.com":
      #   lm1._domainkey.example.com CNAME lm1.dkim.lettermint.com
      #   lm2._domainkey.example.com CNAME lm2.dkim.lettermint.com
      #   lm-bounces.example.com     CNAME bounces.lmta.net
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
        # or LETTERMINT_BASE_URL env var (loaded via ProviderConfig).
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
          raw_records = response['dns_records'] || []
          dns_records = normalize_dns_records(raw_records)

          if raw_records.any? && dns_records.empty?
            log_warn '[lettermint-sender] DNS records returned but none normalized. ' \
                     "Raw keys: #{raw_records.first&.keys&.inspect}"
          end

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
          error_detail = parse_error_response(ex.response_body) || ex.message
          log_error "[lettermint-sender] Provisioning failed for #{domain}: HTTP #{ex.status_code} - #{error_detail}"
          {
            success: false,
            message: "Lettermint API error: #{error_detail}",
            dns_records: [],
            error: "http_#{ex.status_code}: #{error_detail}",
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
        def check_provider_verification_status(mailer_config, credentials:)
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
          domain_entry = find_domain_by_name(client, domain)

          unless domain_entry
            return {
              verified: false,
              status: 'not_found',
              message: "Domain #{domain} not found in Lettermint",
            }
          end

          # Trigger Lettermint to re-check DNS records before reading status.
          # Without this, Lettermint's cached status won't reflect recent DNS changes.
          domain_id = domain_entry['id']
          begin
            client.domains.verify_dns(domain_id)
            log_info "[lettermint-sender] Triggered DNS verification for #{domain} (#{domain_id})"
          rescue StandardError => ex
            # Non-fatal: continue and read whatever status Lettermint has
            log_warn "[lettermint-sender] DNS verify trigger failed for #{domain}: #{ex.message}"
          end

          # Fetch full details with DNS records
          response = client.domains.find(domain_id, include: 'dnsRecords')

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
          error_detail = parse_error_response(ex.response_body) || ex.message
          log_error "[lettermint-sender] Verification check failed for #{domain}: HTTP #{ex.status_code} - #{error_detail}"
          {
            verified: false,
            status: 'error',
            message: "Verification check failed: #{error_detail}",
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
          domain_entry = find_domain_by_name(client, domain)

          unless domain_entry
            # Domain doesn't exist - treat as successful deletion
            return {
              deleted: true,
              message: "Domain #{domain} was already deleted or never existed",
            }
          end

          client.domains.delete(domain_entry['id'])

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
            error_detail = parse_error_response(ex.response_body) || ex.message
            log_error "[lettermint-sender] Deletion failed for #{domain}: HTTP #{ex.status_code} - #{error_detail}"
            {
              deleted: false,
              message: "Deletion failed: #{error_detail}",
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

        # Lazy-loads the Lettermint gem on first use.
        #
        # Avoids loading the gem at boot time when Lettermint isn't configured.
        # Thread-safe via Ruby's require semantics.
        #
        # @return [Module] The Lettermint module
        #
        def lettermint_sdk
          require 'lettermint' unless defined?(::Lettermint)
          ::Lettermint
        end

        # Build Team API client from credentials.
        #
        # Domain provisioning uses the Team API with Bearer auth, NOT the
        # Sending API (x-lettermint-token).
        #
        # @param credentials [Hash] Must include :team_token, optionally :base_url
        # @return [Lettermint::TeamAPI] SDK client instance
        #
        def build_client(credentials)
          team_token = credentials[:team_token] || credentials['team_token']
          base_url   = credentials[:base_url] || credentials['base_url']
          timeout    = credentials[:timeout] || credentials['timeout'] || 30

          lettermint_sdk::TeamAPI.new(
            team_token: team_token,
            base_url: base_url || DEFAULT_BASE_URL,
            timeout: timeout,
          )
        end

        # Find a domain by name using the Team API.
        #
        # WARNING: This implementation does not handle pagination. If the account
        # has many domains and the target domain is not in the first page of
        # results, this lookup will fail to find it. For accounts with many
        # domains, consider implementing cursor-based pagination.
        #
        # @param client [Lettermint::TeamAPI] SDK client instance
        # @param domain [String] Domain name to find (e.g., "example.com")
        # @return [Hash, nil] Domain entry hash with 'id' key, or nil if not found
        #
        def find_domain_by_name(client, domain)
          result = client.domains.list
          result['data']&.find { |d| d['domain'] == domain }
        end

        # Creates a new domain or retrieves existing one on 409 conflict.
        #
        # @param client [Lettermint::TeamAPI] SDK client instance
        # @param domain [String] Domain name (e.g., "example.com")
        # @return [Hash] Parsed API response with id, domain, status, dns_records
        #
        def create_or_get_domain(client, domain)
          response  = client.domains.create(domain: domain)
          domain_id = response['id']

          # Fetch full details with DNS records
          client.domains.find(domain_id, include: 'dnsRecords')
        rescue Lettermint::ValidationError => ex
          # KNOWN SDK QUIRK: Lettermint SDK (as of v0.2.x) sometimes returns
          # ValidationError with message "Domain has already been added" instead
          # of the expected 409 HttpRequestError for duplicate domains. We handle
          # both error types identically to ensure idempotent domain provisioning.
          # NOTE: ValidationError inherits from HttpRequestError, so this rescue
          # must come BEFORE the HttpRequestError rescue.
          msg = ex.message.to_s.downcase
          log_info "[lettermint-sender] Caught ValidationError: #{ex.class} - #{msg.inspect}"
          raise unless msg.include?('already') && msg.include?('added')

          retrieve_existing_domain(client, domain)
        rescue Lettermint::HttpRequestError => ex
          raise unless ex.status_code == 409

          retrieve_existing_domain(client, domain)
        end

        # Retrieves an existing domain by name from Lettermint.
        #
        # @param client [Lettermint::TeamAPI] SDK client instance
        # @param domain [String] Domain name (e.g., "example.com")
        # @return [Hash] Parsed API response with id, domain, status, dns_records
        # @raise [Lettermint::HttpRequestError] if domain not found
        #
        def retrieve_existing_domain(client, domain)
          log_info "[lettermint-sender] Domain #{domain} already exists, retrieving..."
          existing = find_domain_by_name(client, domain)
          raise Lettermint::HttpRequestError.new(message: "Domain #{domain} not found", status_code: 404) unless existing

          client.domains.find(existing['id'], include: 'dnsRecords')
        end

        # Normalize Lettermint DNS records to standard format.
        #
        # Lettermint API returns records as:
        #   [{ "type": "CNAME", "hostname": "lm1._domainkey", "fqdn": "lm1._domainkey.example.com",
        #      "content": "lm1.dkim.lettermint.com", "status": "pending", "id": "..." }, ...]
        #
        # Normalized to consistent shape matching SES/SendGrid:
        #   [{ type: 'CNAME', name: '...', value: '...' }, ...]
        #
        # Maps Lettermint fields: fqdn/hostname → name, content → value.
        #
        # @param records [Array<Hash>] Raw DNS records from Lettermint API
        # @return [Array<Hash>] Normalized records with symbolized keys
        #
        def normalize_dns_records(records)
          return [] if records.nil? || records.empty?

          records.filter_map do |record|
            next unless record.is_a?(Hash)

            rec_type = record['type'] || record[:type]
            # Lettermint API uses 'hostname'/'fqdn'/'content'; fall back to
            # 'name'/'value' for forward compatibility if the API ever changes.
            rec_name = record['fqdn'] || record[:fqdn] ||
                       record['hostname'] || record[:hostname] ||
                       record['name'] || record[:name]
            rec_val  = record['content'] || record[:content] ||
                       record['value'] || record[:value]

            next unless rec_type && rec_name && rec_val

            {
              type: rec_type.upcase,
              name: rec_name,
              value: rec_val,
            }
          end
        end

        # Parse error response body to extract meaningful error message.
        #
        # Lettermint API typically returns JSON errors like:
        #   { "error": "message" } or { "message": "..." } or { "errors": [...] }
        #
        # @param response_body [String, Hash, nil] Raw response body
        # @return [String, nil] Extracted error message or nil
        #
        def parse_error_response(response_body)
          return nil if response_body.nil? || response_body.to_s.empty?

          body = response_body.is_a?(String) ? JSON.parse(response_body) : response_body

          # Lettermint returns { "code": "...", "message": "..." }
          if body['code'] && body['message']
            "#{body['code']}: #{body['message']}"
          elsif body['error']
            body['error']
          elsif body['message']
            body['message']
          elsif body['errors']&.first
            body['errors'].first
          else
            JSON.generate(body)
          end
        rescue JSON::ParserError
          # Not JSON, return raw body (truncated for safety)
          response_body.to_s[0, 200]
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
