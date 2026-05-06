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
    #   updated verification state. Returns the refreshed domain record.
    class VerifyDomain < GetDomain
      SCHEMAS = { response: 'customDomain' }.freeze

      def process
        super

        # Delegate to shared operations layer. Atomic persistence semantics
        # (issue #3080) live there.
        result = Onetime::Operations::VerifyDomain.new(
          domain: custom_domain,
          persist: true,
        ).call

        OT.info "[VerifyDomain.process] #{display_domain} -> validated=#{result.dns_validated}, resolving=#{result.is_resolving}"

        success_data
      end
    end
  end
end
