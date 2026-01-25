# apps/api/domains/cli/list_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Main domains command (list all)
    class DomainsListCommand < Command
      include DomainsHelpers

      desc 'List all custom domains with organization info'

      option :orphaned,
        type: :boolean,
        default: false,
        desc: 'Filter for orphaned domains only'

      option :org_id,
        type: :string,
        default: nil,
        desc: 'Filter by organization ID'

      option :verified,
        type: :boolean,
        default: false,
        desc: 'Filter for verified domains only'

      option :unverified,
        type: :boolean,
        default: false,
        desc: 'Filter for unverified domains only'

      def call(orphaned: false, org_id: nil, verified: false, unverified: false, **)
        boot_application!

        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains    = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        # Apply filters
        filtered_domains = apply_filters(
          all_domains,
          orphaned: orphaned,
          org_id: org_id,
          verified: verified,
          unverified: unverified,
        )

        puts format('%d custom domains', filtered_domains.size)
        return if filtered_domains.empty?

        # Display header
        puts
        puts format('%-40s %-30s %-12s %-10s', 'Domain', 'Organization', 'Status', 'Verified')
        puts '-' * 95

        # Group by display_domain for deduplication
        grouped_domains = filtered_domains.group_by(&:display_domain)

        grouped_domains.sort.each do |display_domain, domains|
          if domains.size == 1
            domain = domains.first
            puts format_domain_row(domain)
          else
            # Multiple records for same domain (duplicates)
            puts format(
              '%-40s %-30s %-12s %-10s',
              "#{display_domain} (#{domains.size} records)",
              'DUPLICATES',
              'CHECK',
              '?',
            )
            domains.each_with_index do |domain, idx|
              org_info = get_organization_info(domain)
              puts format('  [%d] %-37s %-30s', idx + 1, domain.domainid[0..36], org_info)
            end
          end
        end
      end
    end
  end
end

Onetime::CLI.register 'domains', Onetime::CLI::DomainsListCommand
