# lib/onetime/domain_validation/approximated_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # Approximated Strategy - Uses approximated.app API for validation and certs
    #
    # This is the original implementation that delegates to an external service
    # for SSL certificate provisioning and DNS validation.
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
      def initialize(config)
        @config = config
        require 'onetime/cluster'
      end

      def validate_ownership(custom_domain)
        api_key = Onetime::Cluster::Features.api_key

        if api_key.to_s.empty?
          return { validated: false, message: 'Approximated API key not configured' }
        end

        records = [{
          type: 'TXT',
          address: custom_domain.validation_record,
          match_against: custom_domain.txt_validation_value,
        }]

        res = Onetime::Cluster::Approximated.check_records_match_exactly(api_key, records)

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

      def request_certificate(custom_domain)
        api_key      = Onetime::Cluster::Features.api_key
        vhost_target = Onetime::Cluster::Features.vhost_target

        if api_key.to_s.empty?
          return { status: 'error', message: 'Approximated API key not configured' }
        end

        res = Onetime::Cluster::Approximated.create_vhost(
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

      def check_status(custom_domain)
        api_key = Onetime::Cluster::Features.api_key

        if api_key.to_s.empty?
          return { ready: false, message: 'Approximated API key not configured' }
        end

        res = Onetime::Cluster::Approximated.get_vhost_by_incoming_address(
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
    end
  end
end
