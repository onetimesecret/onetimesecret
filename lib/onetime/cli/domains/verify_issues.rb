# lib/onetime/cli/domains/verify_issues.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    module Domains
      # Groups the results of a bulk `domains verify` run by what is wrong
      # with each domain, for the JSON output (`issues` holds the counts,
      # `issue_details` the hostnames).
      #
      # "Could not tell" is listed apart from "no" throughout:
      # dns_indeterminate is not dns_failed, and ssl_unknown (the status check
      # gave no answer about the certificate) is not ssl_failed.
      module VerifyIssues
        KEYS = [
          :orphaned, :org_not_found, :dns_failed, :dns_indeterminate, :dns_expired, :ssl_failed, :ssl_unknown
        ].freeze

        # @param results [Array<Onetime::Operations::VerifyDomain::Result>]
        # @return [Hash{Symbol => Array<String>}] display domains per issue
        def self.tally(results)
          issues = KEYS.to_h { |key| [key, []] }

          results.each do |result|
            matching(result).each { |key| issues[key] << result.domain.display_domain }
          end

          issues
        end

        # @return [Array<Symbol>] the issue keys that apply to one result
        def self.matching(result)
          domain   = result.domain
          orphaned = domain.org_id.to_s.empty?

          {
            orphaned: orphaned,
            org_not_found: !orphaned && domain.primary_organization.nil?,
            dns_failed: result.dns_outcome == :failed,
            dns_indeterminate: result.dns_indeterminate,
            dns_expired: result.confirmation_expired,
            ssl_failed: result.ssl_ready == false,
            ssl_unknown: result.ssl_ready.nil?,
          }.select { |_key, applies| applies }.keys
        end
      end
    end
  end
end
