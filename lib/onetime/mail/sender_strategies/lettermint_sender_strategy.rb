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
      # Lettermint provides DKIM configuration via selector records
      # that must be added to the domain's DNS.
      #
      # API Endpoints (POST /api/v1/domains, GET /api/v1/domains/:domain, etc.):
      #   - POST   /api/v1/domains          Create domain, returns DNS records
      #   - GET    /api/v1/domains/:domain  Get domain status and records
      #   - DELETE /api/v1/domains/:domain  Remove domain
      #
      # Configuration:
      #   api_token: Lettermint API token
      #   base_url:  Custom API base URL (optional)
      #
      class LettermintSenderStrategy < BaseSenderStrategy
        DEFAULT_BASE_URL = 'https://api.lettermint.com'

        def provision_dns_records(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              success: false,
              message: 'Invalid from_address: cannot extract domain',
              dns_records: {},
              error: 'invalid_from_address',
            }
          end

          log_info "[lettermint-sender] Provisioning sender domain for #{domain}"

          client   = build_client(credentials)
          response = client.post(path: '/api/v1/domains', data: { domain: domain })

          # Lettermint returns: { domain:, status:, dns_records: [...], created_at: }
          {
            success: true,
            message: "Domain #{domain} provisioned with Lettermint",
            dns_records: normalize_dns_records(response['dns_records'] || []),
            identity_id: response['domain'],
            provider_data: {
              status: response['status'],
              created_at: response['created_at'],
            },
          }
        rescue Lettermint::HttpRequestError => ex
          handle_api_error(ex, 'provision', domain)
        rescue Lettermint::ValidationError => ex
          {
            success: false,
            message: "Validation error: #{ex.message}",
            dns_records: {},
            error: 'validation_error',
          }
        end

        def check_verification_status(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              verified: false,
              status: 'invalid',
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          log_info "[lettermint-sender] Checking verification status for #{domain}"

          client   = build_client(credentials)
          response = client.get(path: "/api/v1/domains/#{domain}")

          # Lettermint returns: { domain:, status:, verified:, dns_records: [...] }
          verified = response['verified'] == true || response['status'] == 'verified'

          {
            verified: verified,
            status: response['status'] || 'unknown',
            message: verified ? "Domain #{domain} is verified" : "Domain #{domain} pending verification",
            details: {
              dns_records: response['dns_records'],
            },
          }
        rescue Lettermint::HttpRequestError => ex
          handle_verification_error(ex, domain)
        end

        def delete_sender_identity(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              deleted: false,
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          log_info "[lettermint-sender] Deleting sender domain for #{domain}"

          client = build_client(credentials)
          client.delete(path: "/api/v1/domains/#{domain}")

          {
            deleted: true,
            message: "Domain #{domain} removed from Lettermint",
          }
        rescue Lettermint::HttpRequestError => ex
          handle_deletion_error(ex, domain)
        end

        protected

        def validate_config!
          # Validation happens at call time with provided credentials
        end

        private

        # Build Lettermint HTTP client from credentials.
        #
        # @param credentials [Hash] Must include :api_token, optionally :base_url
        # @return [Lettermint::HttpClient]
        #
        def build_client(credentials)
          api_token = credentials[:api_token] || credentials['api_token']
          raise ArgumentError, 'Lettermint API token is required' if api_token.nil? || api_token.empty?

          base_url = credentials[:base_url] || credentials['base_url'] || DEFAULT_BASE_URL
          timeout  = credentials[:timeout] || credentials['timeout'] || 30

          require 'lettermint'
          Lettermint::HttpClient.new(
            api_token: api_token,
            base_url: base_url,
            timeout: timeout,
          )
        end

        # Normalize Lettermint DNS records to standard format.
        #
        # Lettermint returns:
        #   [{ type: 'CNAME', name: 'selector._domainkey', value: 'dkim.lettermint.com' }, ...]
        #
        # @param records [Array<Hash>] Raw DNS records from Lettermint
        # @return [Hash] Normalized records keyed by purpose
        #
        def normalize_dns_records(records)
          return {} if records.nil? || records.empty?

          {
            selectors: records.select { |r| r['type'] == 'CNAME' && r['name']&.include?('_domainkey') },
            txt_records: records.select { |r| r['type'] == 'TXT' },
            all_records: records,
          }
        end

        # Handle API errors for provisioning.
        #
        def handle_api_error(error, operation, domain)
          log_error "[lettermint-sender] #{operation} failed for #{domain}: #{error.message}"

          if error.respond_to?(:status_code) && error.status_code == 409
            # Domain already exists - retrieve existing records
            {
              success: true,
              message: "Domain #{domain} already exists in Lettermint",
              dns_records: {},
              error: 'domain_exists',
              provider_data: { note: 'Use check_verification_status to retrieve DNS records' },
            }
          else
            {
              success: false,
              message: "Lettermint API error: #{error.message}",
              dns_records: {},
              error: 'api_error',
            }
          end
        end

        # Handle API errors for verification status checks.
        #
        def handle_verification_error(error, domain)
          log_error "[lettermint-sender] verification check failed for #{domain}: #{error.message}"

          if error.respond_to?(:status_code) && error.status_code == 404
            {
              verified: false,
              status: 'not_found',
              message: "Domain #{domain} not found in Lettermint. Provision it first.",
            }
          else
            {
              verified: false,
              status: 'error',
              message: "Lettermint API error: #{error.message}",
            }
          end
        end

        # Handle API errors for deletion.
        #
        def handle_deletion_error(error, domain)
          log_error "[lettermint-sender] deletion failed for #{domain}: #{error.message}"

          if error.respond_to?(:status_code) && error.status_code == 404
            # Domain doesn't exist - treat as successful deletion
            {
              deleted: true,
              message: "Domain #{domain} not found (already deleted or never existed)",
            }
          else
            {
              deleted: false,
              message: "Lettermint API error: #{error.message}",
            }
          end
        end
      end
    end
  end
end
