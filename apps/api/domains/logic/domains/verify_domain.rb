# apps/api/domains/logic/domains/verify_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/features'
require 'onetime/domain_validation/strategy'
require 'onetime/operations/verify_domain'
require_relative 'get_domain'

module DomainsAPI::Logic
  module Domains
    # Verify Custom Domain
    #
    # @api Triggers DNS and SSL verification for a custom domain. Checks
    #   TXT record ownership and resolving status, then persists the
    #   updated verification state. Returns the refreshed domain record,
    #   with the outcome of the TXT check in details.
    class VerifyDomain < GetDomain
      SCHEMAS = { response: 'customDomain' }.freeze

      attr_reader :result

      def process
        super

        # Delegate to shared operations layer. Atomic persistence semantics
        # (issue #3080) live there.
        @result = Onetime::Operations::VerifyDomain.new(
          domain: custom_domain,
          persist: true,
        ).call

        OT.info "[VerifyDomain.process] #{display_domain} -> validated=#{result.dns_validated}, indeterminate=#{result.dns_indeterminate}, resolving=#{result.is_resolving}"

        success_data
      end

      # GetDomain's payload plus what this check learned about the TXT record.
      # The record alone cannot say it: a check that produced no answer leaves
      # `verified` as it was, which reads the same as a definitive "no".
      def success_data
        data           = super
        data[:details] = data[:details].merge(verification_details)
        data
      end

      private

      # 'dns_outcome' is one of validated / confirmation_expired /
      # indeterminate / override_held / failed (see
      # Onetime::Operations::VerifyDomain::Result#dns_outcome).
      # 'dns_indeterminate' is true for both indeterminate and
      # confirmation_expired: the check could not be completed.
      #
      # Empty before the operation has run (GetDomain#process builds its own
      # success_data first).
      def verification_details
        return {} if result.nil?

        {
          'dns_outcome' => result.dns_outcome.to_s,
          'dns_indeterminate' => result.dns_indeterminate == true,
        }
      end
    end
  end
end
