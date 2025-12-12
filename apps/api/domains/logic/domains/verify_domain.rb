# apps/api/domains/logic/domains/verify_domain.rb
#
# frozen_string_literal: true

require 'onetime/cluster'
require 'onetime/domain_validation/strategy'
require_relative 'get_domain'

module DomainsAPI::Logic
  module Domains
    class VerifyDomain < GetDomain
      def process
        super

        # Use the configured strategy to refresh status and validate
        strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)

        refresh_status(strategy)
        refresh_validation(strategy)

        success_data
      end

      # Refresh the domain status (SSL, resolving, etc.)
      def refresh_status(strategy)
        result = strategy.check_status(custom_domain)

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

      # Validate domain ownership via TXT record
      def refresh_validation(strategy)
        result = strategy.validate_ownership(custom_domain)

        OT.info "[VerifyDomain.refresh_validation] #{display_domain} -> #{result[:validated]}"

        # Update verification status
        custom_domain.verified! result[:validated]

        # Emit telemetry event for stats tracking
        emit_verification_telemetry(result[:validated], result[:message])
      rescue StandardError => ex
        OT.le "[VerifyDomain.refresh_validation] Error: #{ex.message}"
      end

      # Emit telemetry event for domain verification
      # @param validated [Boolean] Whether verification succeeded
      # @param message [String, nil] Additional context
      def emit_verification_telemetry(validated, message = nil)
        event_type = validated ? 'domain.verified' : 'domain.verification_failed'
        data = {
          domain: display_domain,
          organization_id: custom_domain.org_id,
        }
        data[:reason] = message if message && !validated

        Onetime::Jobs::Publisher.enqueue_transient(event_type, data)
      rescue StandardError => ex
        # Telemetry failures should never break the main flow
        OT.ld "[VerifyDomain] Telemetry error: #{ex.message}"
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
