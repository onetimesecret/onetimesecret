# apps/api/domains/cli/list_command.rb
#
# frozen_string_literal: true

require 'json'
require_relative 'helpers'

module Onetime
  module CLI
    # Main domains command (list all)
    class DomainsListCommand < Command
      include DomainsHelpers

      SORT_FIELDS = %w[domain created updated org status].freeze

      desc 'List all custom domains with organization info'

      option :orphaned,
        type: :boolean,
        default: false,
        desc: 'Filter for orphaned domains only'

      option :org_id,
        type: :string,
        default: nil,
        desc: 'Filter by organization ID (internal)'

      option :org_extid,
        type: :string,
        default: nil,
        desc: 'Filter by organization external ID'

      option :verified,
        type: :boolean,
        default: false,
        desc: 'Filter for verified domains only'

      option :unverified,
        type: :boolean,
        default: false,
        desc: 'Filter for unverified domains only'

      option :sort,
        type: :string,
        default: 'domain',
        desc: "Sort by field: #{SORT_FIELDS.join(', ')}"

      option :desc,
        type: :boolean,
        default: false,
        desc: 'Sort descending (default: ascending)'

      option :limit,
        type: :integer,
        default: nil,
        desc: 'Limit number of results'

      option :vhost,
        type: :boolean,
        default: false,
        desc: 'Include vhost details as JSON'

      def call(orphaned: false, org_id: nil, org_extid: nil, verified: false, unverified: false,
               sort: 'domain', desc: false, limit: nil, vhost: false, **)
        boot_application!

        # Batch load all domains using Familia v2.9.0's each_record
        all_domains = []
        Onetime::CustomDomain.instances.each_record { |domain| all_domains << domain }

        # Resolve org_extid to org_id if provided
        resolved_org_id = resolve_org_filter(org_id, org_extid)
        return if resolved_org_id == :not_found

        # Apply filters
        filtered_domains = apply_filters(
          all_domains,
          orphaned: orphaned,
          org_id: resolved_org_id,
          verified: verified,
          unverified: unverified,
        )

        # Pre-load organizations to avoid N+1 queries during sort/display
        @org_cache = preload_organizations(filtered_domains)

        # Apply sorting
        sorted_domains = sort_domains(filtered_domains, sort, desc)

        # Apply limit
        sorted_domains = sorted_domains.first(limit) if limit

        puts format(
          '%d custom domains%s',
          sorted_domains.size,
          limit ? " (limited from #{filtered_domains.size})" : '',
        )
        return if sorted_domains.empty?

        display_domain_index_table(sorted_domains, show_vhost: vhost)
      end

      private

      def resolve_org_filter(org_id, org_extid)
        return org_id if org_id

        return nil unless org_extid

        org = Onetime::Organization.find_by_extid(org_extid)
        unless org
          puts "Error: Organization with extid '#{org_extid}' not found"
          exit 1
        end
        org.org_id
      end

      def preload_organizations(domains)
        org_ids = domains.map(&:org_id).compact.uniq
        cache   = {}
        org_ids.each do |oid|
          next if oid.to_s.empty?

          cache[oid] ||= Onetime::Organization.load(oid)
        end
        cache
      end

      def cached_org_info(domain)
        return '(orphaned)' if domain.org_id.to_s.empty?

        org = @org_cache&.[](domain.org_id)
        return "(org: #{domain.org_id})" unless org

        org.display_name || org.org_id
      end

      def sort_domains(domains, sort_field, descending)
        unless SORT_FIELDS.include?(sort_field)
          puts "Warning: Invalid sort field '#{sort_field}', using 'domain'"
          sort_field = 'domain'
        end

        sorted = domains.sort_by do |d|
          case sort_field
          when 'domain'
            d.display_domain.to_s.downcase
          when 'created'
            d.created.to_i
          when 'updated'
            d.updated.to_i
          when 'org'
            cached_org_info(d).downcase
          when 'status'
            d.verification_state.to_s
          end
        end

        descending ? sorted.reverse : sorted
      end

      def display_domain_index_table(domains, show_vhost: false)
        puts
        if show_vhost
          puts format('%-40s %-25s %-12s %-8s  %s', 'Domain', 'Organization', 'Status', 'Verified', 'Vhost')
          puts '-' * 120
        else
          puts format('%-40s %-30s %-12s %-10s', 'Domain', 'Organization', 'Status', 'Verified')
          puts '-' * 95
        end

        # Group by display_domain for deduplication
        grouped_domains = domains.group_by(&:display_domain)
        # Preserve sort order by iterating in original order
        seen            = Set.new
        domains.each do |domain|
          dd = domain.display_domain
          next if seen.include?(dd)

          seen << dd
          group = grouped_domains[dd]

          if group.size == 1
            puts format_domain_row_extended(domain, show_vhost: show_vhost)
          else
            display_duplicate_group(dd, group, show_vhost: show_vhost)
          end
        end
      end

      def truncate(str, max_len)
        str.to_s[0, max_len]
      end

      def format_domain_row_extended(domain, show_vhost: false)
        org_info = cached_org_info(domain)
        status   = domain.verification_state || 'unknown'
        verified = domain.verified == true || domain.verified.to_s == 'true' ? 'yes' : 'no'

        if show_vhost
          vhost_json = format_vhost_json(domain)
          format(
            '%-40s %-25s %-12s %-8s  %s',
            truncate(domain.display_domain, 40),
            truncate(org_info, 25),
            truncate(status, 12),
            verified,
            vhost_json,
          )
        else
          format(
            '%-40s %-30s %-12s %-10s',
            truncate(domain.display_domain, 40),
            truncate(org_info, 30),
            truncate(status, 12),
            verified,
          )
        end
      end

      def format_vhost_json(domain)
        vhost_data = domain.parse_vhost
        return '-' if vhost_data.nil? || vhost_data.empty?

        JSON.generate(vhost_data)
      rescue StandardError => ex
        OT.le("Vhost JSON error for #{domain.domainid}: #{ex.message}")
        "(error: #{truncate(ex.message, 50)})"
      end

      def display_duplicate_group(display_domain, domains, show_vhost: false)
        if show_vhost
          puts format(
            '%-40s %-25s %-12s %-8s  %s',
            "#{display_domain} (#{domains.size} records)",
            'DUPLICATES',
            'CHECK',
            '?',
            '-',
          )
        else
          puts format(
            '%-40s %-30s %-12s %-10s',
            "#{display_domain} (#{domains.size} records)",
            'DUPLICATES',
            'CHECK',
            '?',
          )
        end
        domains.each_with_index do |domain, idx|
          org_info = cached_org_info(domain)
          puts format('  [%d] %-37s %-30s', idx + 1, truncate(domain.domainid, 37), org_info)
        end
      end
    end
  end
end

Onetime::CLI.register 'domains list', Onetime::CLI::DomainsListCommand
