# apps/api/domains/cli/orphaned_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List orphaned domains
    class DomainsOrphanedCommand < Command
      include DomainsHelpers

      desc 'List domains without organization ownership'

      def call(**)
        boot_application!

        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains    = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        orphaned_domains = all_domains.select { |d| d.org_id.to_s.empty? }

        puts "#{orphaned_domains.size} orphaned custom domains found"
        return if orphaned_domains.empty?

        puts
        puts format('%-40s %-12s %-10s %-20s', 'Domain', 'Status', 'Verified', 'Created')
        puts '-' * 85

        orphaned_domains.sort_by(&:display_domain).each do |domain|
          status   = domain.verification_state || 'unknown'
          verified = domain.verified || 'false'
          created  = format_timestamp(domain.created)

          puts format(
            '%-40s %-12s %-10s %-20s',
            domain.display_domain,
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
