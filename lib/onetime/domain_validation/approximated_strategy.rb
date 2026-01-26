# lib/onetime/domain_validation/approximated_strategy.rb
#
# frozen_string_literal: true

require_relative 'features'
require_relative 'approximated_client'

module Onetime
  module DomainValidation
    # ApproximatedStrategy - Uses approximated.app API for validation and certs.
    #
    # Design Decision: Dependency injection for the API client.
    #
    # The client is injected at construction, defaulting to ApproximatedClient.
    # This enables:
    # - Unit testing with mock clients
    # - Easy swapping of HTTP implementations
    # - Clear separation between strategy logic and HTTP transport
    #
    # Configuration is read from DomainValidation::Features.
    #
    # The #check_status method returns a vhost Hash stored on CustomDomain:
    #
    #   {
    #     "ready": true,
    #     "has_ssl": true,
    #     "is_resolving": true,
    #     "status": "ACTIVE_SSL",
    #     "status_message": "Human-readable status",
    #     "data": {}
    #   }
    #
    class ApproximatedStrategy < BaseStrategy
      attr_reader :client, :config

      # @param config [Hash] Application configuration (typically OT.conf)
      # @param client [Module] HTTP client module (default: ApproximatedClient)
      #
      def initialize(config, client: ApproximatedClient)
        @config = config
        @client = client
      end

      # Validates domain ownership via TXT record.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def validate_ownership(custom_domain)
        api_key = Features.api_key

        if api_key.to_s.empty?
          return { validated: false, message: 'Approximated API key not configured' }
        end

        records = [{
          type: 'TXT',
          address: custom_domain.validation_record,
          match_against: custom_domain.txt_validation_value,
        }]

        res = client.check_records_match_exactly(api_key, records)

        if res.code == 200
          payload       = res.parsed_response
          match_records = payload['records']
          found_match   = match_records.any? { |record| record['match'] == true }

          {
            validated: found_match,
            message: found_match ? 'TXT record validated' : 'TXT record not found or mismatch',
            data: match_records,
          }
        else
          {
            validated: false,
            message: "Validation check failed: #{res.code}",
            error: res.parsed_response,
          }
        end
      rescue StandardError => ex
        OT.le "[ApproximatedStrategy] Error validating #{custom_domain.display_domain}: #{ex.message}"
        { validated: false, message: "Error: #{ex.message}" }
      end

      # Requests SSL certificate by creating a vhost.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#request_certificate
      #
      def request_certificate(custom_domain)
        api_key      = Features.api_key
        vhost_target = Features.vhost_target

        if api_key.to_s.empty?
          return { status: 'error', message: 'Approximated API key not configured' }
        end

        if vhost_target.to_s.empty?
          OT.le '[ApproximatedStrategy] vhost_target not configured (set APPROXIMATED_VHOST_TARGET)'
          return { status: 'error', message: 'Approximated vhost_target not configured' }
        end

        res = client.create_vhost(
          api_key,
          custom_domain.display_domain,
          vhost_target,
          '443',
        )

        if res.code == 200
          payload = res.parsed_response
          {
            status: 'requested',
            message: 'Virtual host created',
            data: payload['data'],
          }
        else
          {
            status: 'error',
            message: "Failed to create vhost: #{res.code}",
            error: res.parsed_response,
          }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy] Error requesting cert for #{custom_domain.display_domain}: #{ex.message}"
        { status: 'error', message: "Error: #{ex.message}" }
      end

      # Checks current domain status from Approximated.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#check_status
      #
      def check_status(custom_domain)
        api_key = Features.api_key

        if api_key.to_s.empty?
          return { ready: false, message: 'Approximated API key not configured' }
        end

        res = client.get_vhost_by_incoming_address(
          api_key,
          custom_domain.display_domain,
        )

        if res.code == 200
          payload = res.parsed_response
          data    = payload['data']

          {
            ready: data['status'] == 'ACTIVE_SSL',
            has_ssl: data['has_ssl'],
            is_resolving: data['is_resolving'],
            status: data['status'],
            status_message: data['status_message'],
            data: data,
          }
        else
          {
            ready: false,
            message: "Status check failed: #{res.code}",
            error: res.parsed_response,
          }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy] Error checking status for #{custom_domain.display_domain}: #{ex.message}"
        { ready: false, message: "Error: #{ex.message}" }
      end

      # Deletes the vhost from Approximated.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#delete_vhost
      #
      def delete_vhost(custom_domain)
        api_key = Features.api_key

        if api_key.to_s.empty?
          OT.info '[ApproximatedStrategy.delete_vhost] API key not configured'
          return { deleted: false, message: 'Approximated API key not configured' }
        end

        res = client.delete_vhost(api_key, custom_domain.display_domain)

        if res.success?
          payload = res.parsed_response
          OT.info "[ApproximatedStrategy.delete_vhost] Deleted #{custom_domain.display_domain}"
          {
            deleted: true,
            message: "Deleted vhost: #{custom_domain.display_domain}",
            data: payload,
          }
        else
          OT.le "[ApproximatedStrategy.delete_vhost] Failed: #{res.code} for #{custom_domain.display_domain}"
          { deleted: false, message: "Failed to delete vhost: status #{res.code}" }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy.delete_vhost] Error: #{custom_domain.display_domain} - #{ex.message}"
        { deleted: false, message: "Error: #{ex.message}" }
      end

      # Retrieves DNS widget token from Approximated.
      #
      # @return [Hash] See BaseStrategy#get_dns_widget_token
      #
      def get_dns_widget_token
        api_key = Features.api_key

        if api_key.to_s.empty?
          return { available: false, message: 'Approximated API key not configured' }
        end

        res = client.get_dns_widget_token(api_key)

        if res.code == 200
          {
            available: true,
            token: res.parsed_response['token'],
            api_url: 'https://cloud.approximated.app/api/dns',
            expires_in: 600, # 10 minutes
          }
        else
          {
            available: false,
            message: "Failed to get token: #{res.code}",
          }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy.get_dns_widget_token] Error: #{ex.message}"
        { available: false, message: "Error: #{ex.message}" }
      end

      # @return [Boolean] true - Approximated supports the DNS widget
      def supports_dns_widget?
        true
      end

      # @return [Boolean] true - Approximated actively manages certificates
      def manages_certificates?
        true
      end
    end
  end
end
