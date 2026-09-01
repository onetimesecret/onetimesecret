# lib/onetime/cli/domains/list_command.rb
#
# frozen_string_literal: true

# List all custom domains with organization info — the CLI peer of
# `GET /api/colonel/domains`. Both adapters call the same op
# (Onetime::Operations::Domains::List), which owns the bounded, index-backed
# read + the wire-shaped rows. This command owns only CLI concerns: the
# operator-facing filters, sorting, and the duplicate-record diagnostic.
#
# Usage:
#   bin/ots domains list
#   bin/ots domains list --orphaned
#   bin/ots domains list --org-extid on123abc
#   bin/ots domains list --status pending --unverified
#   bin/ots domains list --sort created --desc --limit 20
#   bin/ots domains list --vhost
#   bin/ots domains list --json
#
# CLI mode drives the op with `per_page: nil` (full population, unpaginated):
# the duplicate-record diagnostic groups by display_domain across the WHOLE set
# and cannot page. The remaining filters/sort/limit apply in Ruby on the rows
# the op returns, preserving the incumbent CLI behaviour exactly.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/list'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsListCommand < Command
      include Domains::Shared

      SORT_FIELDS = %w[domain created updated org status].freeze

      desc 'List all custom domains with organization info'

      option :orphaned,
        type: :boolean,
        default: false,
        desc: 'Filter for orphaned domains only'
      option :org_id,
        type: :string,
        default: nil,
        desc: 'Filter by organization ID (internal objid)'
      option :org_extid,
        type: :string,
        default: nil,
        desc: 'Filter by organization external ID'
      option :status,
        type: :string,
        default: nil,
        desc: 'Filter by verification_state (verified, pending, resolving, unverified)'
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
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON for scripting'

      def call(orphaned: false, org_id: nil, org_extid: nil, status: nil,
               verified: false, unverified: false, sort: 'domain', desc: false,
               limit: nil, vhost: false, json: false, **)
        boot_application!

        resolved_org_id = resolve_org_filter(org_id, org_extid, json: json)

        # Full population, unpaginated, wire-shaped rows from the shared op.
        rows = Onetime::Operations::Domains::List.new(per_page: nil).call.domains

        rows = apply_row_filters(
          rows,
          orphaned: orphaned,
          org_id: resolved_org_id,
          status: status,
          verified: verified,
          unverified: unverified,
        )
        rows = sort_rows(rows, sort, desc)

        filtered_count = rows.size
        rows           = rows.first(limit) if limit

        OT.info "[cli-domains-list] shown=#{rows.size} filtered=#{filtered_count}"

        if json
          puts JSON.pretty_generate(count: rows.size, filtered_count: filtered_count, domains: rows)
          return
        end

        puts format(
          '%d custom domains%s',
          rows.size,
          limit ? " (limited from #{filtered_count})" : '',
        )
        return if rows.empty?

        display_domain_index_table(rows, show_vhost: vhost)
      end

      private

      def resolve_org_filter(org_id, org_extid, json:)
        return org_id if org_id
        return nil unless org_extid

        org = Onetime::Organization.find_by_extid(org_extid)
        error_exit("Organization with extid '#{org_extid}' not found", json: json) unless org
        org.org_id
      end

      # Legacy DomainsHelpers#apply_filters, adapted to the op's row hashes.
      def apply_row_filters(rows, orphaned:, org_id:, status:, verified:, unverified:)
        rows = rows.select { |r| r[:org_id].to_s.empty? } if orphaned
        rows = rows.select { |r| r[:org_id].to_s == org_id.to_s } if org_id
        rows = rows.select { |r| r[:verification_state].to_s == status.to_s } if status
        if verified
          rows = rows.select { |r| r[:verified] == true }
        elsif unverified
          rows = rows.reject { |r| r[:verified] == true }
        end
        rows
      end

      def sort_rows(rows, sort_field, descending)
        unless SORT_FIELDS.include?(sort_field)
          puts "Warning: Invalid sort field '#{sort_field}', using 'domain'"
          sort_field = 'domain'
        end

        sorted = rows.sort_by do |r|
          case sort_field
          when 'domain'  then r[:display_domain].to_s.downcase
          when 'created' then r[:created].to_i
          when 'updated' then r[:updated].to_i
          when 'org'     then org_info(r).downcase
          when 'status'  then r[:verification_state].to_s
          end
        end

        descending ? sorted.reverse : sorted
      end

      # Mirrors the legacy cached_org_info: display name, or an orphaned/missing
      # marker. The op already resolved org_name ('Unknown' when the org row is
      # gone), so no second lookup is needed here.
      def org_info(row)
        return '(orphaned)' if row[:org_id].to_s.empty?
        return "(org: #{row[:org_id]})" if row[:org_name].to_s.empty? || row[:org_name] == 'Unknown'

        row[:org_name]
      end

      def display_domain_index_table(rows, show_vhost: false)
        puts
        if show_vhost
          puts format('%-40s %-25s %-12s %-8s  %s', 'Domain', 'Organization', 'Status', 'Verified', 'Vhost')
          puts '-' * 120
        else
          puts format('%-40s %-30s %-12s %-10s', 'Domain', 'Organization', 'Status', 'Verified')
          puts '-' * 95
        end

        grouped = rows.group_by { |r| r[:display_domain] }
        seen    = Set.new
        rows.each do |row|
          dd = row[:display_domain]
          next if seen.include?(dd)

          seen << dd
          group = grouped[dd]

          if group.size == 1
            puts format_domain_row(row, show_vhost: show_vhost)
          else
            display_duplicate_group(dd, group, show_vhost: show_vhost)
          end
        end
      end

      def truncate(str, max_len)
        str.to_s[0, max_len]
      end

      def format_domain_row(row, show_vhost: false)
        info     = org_info(row)
        status   = row[:verification_state].to_s.empty? ? 'unknown' : row[:verification_state]
        verified = row[:verified] ? 'yes' : 'no'

        if show_vhost
          format(
            '%-40s %-25s %-12s %-8s  %s',
            truncate(row[:display_domain], 40),
            truncate(info, 25),
            truncate(status, 12),
            verified,
            vhost_json(row),
          )
        else
          format(
            '%-40s %-30s %-12s %-10s',
            truncate(row[:display_domain], 40),
            truncate(info, 30),
            truncate(status, 12),
            verified,
          )
        end
      end

      # --vhost is a niche diagnostic and the op's rows do not carry the raw
      # vhost, so re-load only the displayed row's domain to parse it.
      def vhost_json(row)
        domain = Onetime::CustomDomain.find_by_identifier(row[:domain_id])
        return '-' unless domain

        vhost_data = domain.parse_vhost
        return '-' if vhost_data.nil? || vhost_data.empty?

        JSON.generate(vhost_data)
      rescue StandardError => ex
        OT.le("Vhost JSON error for #{row[:domain_id]}: #{ex.message}")
        "(error: #{truncate(ex.message, 50)})"
      end

      def display_duplicate_group(display_domain, group, show_vhost: false)
        if show_vhost
          puts format(
            '%-40s %-25s %-12s %-8s  %s',
            "#{display_domain} (#{group.size} records)",
            'DUPLICATES',
            'CHECK',
            '?',
            '-',
          )
        else
          puts format(
            '%-40s %-30s %-12s %-10s',
            "#{display_domain} (#{group.size} records)",
            'DUPLICATES',
            'CHECK',
            '?',
          )
        end
        group.each_with_index do |row, idx|
          puts format('  [%d] %-37s %-30s', idx + 1, truncate(row[:domain_id], 37), org_info(row))
        end
      end
    end

    register 'domains list', DomainsListCommand
  end
end
