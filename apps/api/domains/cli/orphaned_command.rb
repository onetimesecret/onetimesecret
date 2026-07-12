# apps/api/domains/cli/orphaned_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/domains/orphaned_scan'

module Onetime
  module CLI
    # List orphaned domains
    class DomainsOrphanedCommand < Command
      include DomainsHelpers

      desc 'List domains without organization ownership'

      def call(**)
        boot_application!

        # Delegate to the single op implementation (read-only, no audit). Passing
        # per_page: nil returns the full sorted collection — preserving the CLI's
        # "list all orphaned, sorted by display_domain" output.
        result           = Onetime::Operations::Domains::OrphanedScan.new(per_page: nil).call
        orphaned_domains = result.domains

        puts "#{orphaned_domains.size} orphaned custom domains found"
        return if orphaned_domains.empty?

        puts
        puts format('%-40s %-12s %-10s %-20s', 'Domain', 'Status', 'Verified', 'Created')
        puts '-' * 85

        orphaned_domains.each do |domain|
          status   = domain[:verification_state].to_s.empty? ? 'unknown' : domain[:verification_state]
          verified = domain[:verified] ? 'true' : 'false'
          created  = format_timestamp(domain[:created])

          puts format(
            '%-40s %-12s %-10s %-20s',
            domain[:display_domain],
            status,
            verified,
            created,
          )
        end
      end
    end
  end
end

Onetime::CLI.register 'domains orphaned', Onetime::CLI::DomainsOrphanedCommand
