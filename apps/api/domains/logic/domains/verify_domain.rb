# apps/api/domains/logic/domains/verify_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/features'
require 'onetime/domain_validation/strategy'
require 'onetime/operations/verify_domain'
require_relative 'get_domain'

module DomainsAPI::Logic
  module Domains
    class VerifyDomain < GetDomain
      def process
        super

        # Delegate to shared operations layer
        result = Onetime::Operations::VerifyDomain.new(
          domain: custom_domain,
          persist: true,
        ).call

        OT.info "[VerifyDomain.process] #{display_domain} -> validated=#{result.dns_validated}, resolving=#{result.is_resolving}"

        success_data
      end

      # Refresh the domain status (SSL, resolving, etc.)
      # If the vhost doesn't exist in Approximated, try to create it first.
      # @deprecated Use Onetime::Operations::VerifyDomain directly
      def refresh_status(strategy)
        result = strategy.check_status(custom_domain)

        # Check if vhost not found (404) - the strategy returns this as a message
        if vhost_not_found?(result)
          OT.info "[VerifyDomain.refresh_status] Vhost not found for #{display_domain}, attempting to create"
          ensure_vhost_exists(strategy)
          # Re-check status after creating vhost
          result = strategy.check_status(custom_domain)
        end

        OT.info "[VerifyDomain.refresh_status] #{display_domain} -> #{result[:ready]}"

        # Update custom domain with status information
        custom_domain.vhost = result[:data].to_json if result[:data]

        # Handle boolean values correctly (including false)
        unless result[:is_resolving].nil?
          custom_domain.resolving = result[:is_resolving].to_s
        end

        custom_domain.updated = OT.now.to_i
        custom_domain.save
      rescue StandardError => ex
        OT.le "[VerifyDomain.refresh_status] Error: #{ex.message}"
      end

      # Check if the result indicates vhost was not found (404 from Approximated)
      # @deprecated Use Onetime::Operations::VerifyDomain directly
      def vhost_not_found?(result)
        return false unless result.is_a?(Hash)

        message = result[:message].to_s
        message.include?('Could not find Virtual Host')
      end

      # Ensure the vhost exists in Approximated, creating it if necessary.
      # This handles cases where the initial vhost creation failed during domain addition.
      # @deprecated Use Onetime::Operations::VerifyDomain directly
      def ensure_vhost_exists(strategy)
        result = strategy.request_certificate(custom_domain)

        if %w[requested success].include?(result[:status])
          OT.info "[VerifyDomain.ensure_vhost_exists] Created vhost for #{display_domain}"

          # Store the vhost data if returned
          if result[:data]
            custom_domain.vhost   = result[:data].to_json
            custom_domain.updated = OT.now.to_i
            custom_domain.save
          end
        else
          OT.le "[VerifyDomain.ensure_vhost_exists] Failed to create vhost: #{result[:message]}"
        end
      rescue StandardError => ex
        OT.le "[VerifyDomain.ensure_vhost_exists] Error: #{ex.message}"
      end

      # Validate domain ownership via TXT record
      # @deprecated Use Onetime::Operations::VerifyDomain directly
      def refresh_validation(strategy)
        result = strategy.validate_ownership(custom_domain)

        OT.info "[VerifyDomain.refresh_validation] #{display_domain} -> #{result[:validated]}"

        # Update verification status
        custom_domain.verified! result[:validated]
      rescue StandardError => ex
        OT.le "[VerifyDomain.refresh_validation] Error: #{ex.message}"
      end

      # Legacy methods for backward compatibility
      # @deprecated Use refresh_status instead
      def refresh_vhost
        strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
        refresh_status(strategy)
      end

      # @deprecated Use refresh_validation instead
      def refresh_txt_record_status
        strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
        refresh_validation(strategy)
      end
    end
  end
end
