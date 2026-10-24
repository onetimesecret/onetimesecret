# lib/onetime/cli/org/list_command.rb
#
# frozen_string_literal: true

# List organizations, optionally filtered by owner email or plan.
#
# Usage:
#   bin/ots organizations list                                # First 50 organizations
#   bin/ots organizations list --owner acme.com --run         # Owner email contains "acme.com"
#   bin/ots organizations list --plan identity_plus_v1 --run  # Exact plan id
#   bin/ots organizations list --verbose                      # With members and domains
#   bin/ots organizations list --limit 200 --json             # JSON output
#
# --owner and --plan have no index to read: matching loads organization
# records one at a time (plus each owner for --owner) until --limit match, so
# a rare match walks every organization. A filtered listing is therefore a
# dry run unless --run is given: it reports the size of the walk and loads
# nothing. The unfiltered listing loads at most --limit records and needs no
# --run.
#
# One organization in depth: `bin/ots organizations show ORG`.

require 'json'
# Org::Shared must exist before `include Org::Shared` below. Required here (not
# only from the lib/onetime/cli.rb manifest) so this file cannot be loaded in a
# broken order.
require_relative 'shared'

module Onetime
  module CLI
    class OrgListCommand < Command
      # error_exit (json-aware) + member_rows / format_member_row.
      include Org::Shared

      desc 'List organizations (filter by owner email or plan)'

      option :owner,
        type: :string,
        default: nil,
        desc: 'Filter by owner email (case-insensitive substring)'

      option :plan,
        type: :string,
        default: nil,
        desc: 'Filter by plan ID (exact match)'

      option :limit,
        type: :integer,
        default: 50,
        desc: 'Maximum organizations to list'

      option :verbose,
        type: :boolean,
        default: false,
        desc: 'Show members and domains under each organization'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Run an --owner/--plan scan (default: dry run, nothing loaded)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(owner: nil, plan: nil, limit: 50, verbose: false, run: false, json: false, **)
        boot_application!

        # A negative --limit reaches Array#take, which raises on a negative
        # size; a zero limit is a silently empty listing. Reject both here.
        error_exit('--limit must be a positive integer', json: json) if limit.to_i < 1

        if (owner || plan) && !run
          return output_scan_plan(owner: owner, plan: plan, limit: limit.to_i, json: json)
        end

        list_organizations(owner: owner, plan: plan, limit: limit.to_i, verbose: verbose, json: json)
      end

      private

      def output_scan_plan(owner:, plan:, limit:, json:)
        total = Onetime::Organization.instances.count

        if json
          puts JSON.pretty_generate(total: total, dry_run: true, owner: owner, plan: plan, limit: limit)
          return
        end

        puts format('%d total organizations', total)
        puts
        puts "Matching #{filter_description(owner, plan)} loads up to #{total} organization records " \
             "until #{limit} match."
        puts 'Dry run - nothing loaded. Re-run with --run to scan.'
      end

      def list_organizations(owner: nil, plan: nil, limit: 50, verbose: false, json: false)
        all_org_ids = Onetime::Organization.instances.all
        orgs        = load_organizations(all_org_ids, owner: owner, plan: plan, limit: limit)

        if json
          output_json(all_org_ids.size, orgs, verbose: verbose)
        else
          output_text(all_org_ids.size, orgs, owner: owner, plan: plan, limit: limit, verbose: verbose)
        end
      end

      def output_text(total, orgs, owner:, plan:, limit:, verbose:)
        puts format('%d total organizations', total)
        puts

        filtered = owner || plan
        if filtered
          puts format('Found %d organizations matching %s (limit: %d)', orgs.size, filter_description(owner, plan), limit)
          puts
        end

        return if orgs.empty?

        puts format('%-32s %-20s %-20s %-18s', 'ExtID', 'Display Name', 'Plan', 'Stripe Customer')
        puts '-' * 95

        orgs.each do |org|
          puts format('%-32s %-20s %-20s %-18s', org.extid, truncate(org.display_name.to_s, 18), plan_label(org), stripe_label(org))
          print_verbose_detail(org) if verbose
        end

        print_limit_note(total, orgs.size, limit, filtered: filtered)
      end

      def print_limit_note(total, shown, limit, filtered:)
        return unless total > limit

        if !filtered
          puts
          puts "(showing #{limit} of #{total} - use --limit to see more)"
        elsif shown >= limit
          puts
          puts "(stopped at --limit #{limit}; more organizations may match)"
        end
      end

      def print_verbose_detail(org)
        member_rows(org).each { |row| puts format_member_row(row, indent: '    member: ') }
        org.list_domains.each do |domain|
          puts format('    domain: %s  state=%s', domain.display_domain, domain.verification_state)
        end
      end

      def output_json(total, orgs, verbose:)
        payload = {
          total: total,
          count: orgs.size,
          organizations: orgs.map { |org| json_entry(org, verbose: verbose) },
        }
        puts JSON.pretty_generate(payload)
      end

      def json_entry(org, verbose:)
        entry = {
          extid: org.extid,
          display_name: org.display_name,
          planid: presence(org.planid),
          stripe_customer_id: presence(org.stripe_customer_id),
        }
        return entry unless verbose

        entry.merge(
          members: member_rows(org),
          domains: org.list_domains.map do |domain|
            { extid: domain.extid, display_domain: domain.display_domain, verification_state: domain.verification_state.to_s }
          end,
        )
      end

      def plan_label(org)
        org.planid.to_s.empty? ? 'free' : truncate(org.planid.to_s, 18)
      end

      def stripe_label(org)
        org.stripe_customer_id.to_s.empty? ? '-' : org.stripe_customer_id
      end

      def presence(value)
        value.to_s.empty? ? nil : value
      end

      def truncate(str, max_length)
        return str if str.length <= max_length

        "#{str[0, max_length - 1]}…"
      end

      def filter_description(owner, plan)
        [owner && "owner=#{owner}", plan && "plan=#{plan}"].compact.join(', ')
      end

      def load_organizations(all_org_ids, owner:, plan:, limit:)
        if owner || plan
          load_filtered_organizations(all_org_ids, owner: owner, plan: plan, limit: limit)
        else
          all_org_ids.take(limit).filter_map { |oid| Onetime::Organization.load(oid) }
        end
      end

      # Streams the whole instances index until `limit` matches are found, so
      # the limit applies AFTER the filter.
      def load_filtered_organizations(all_org_ids, owner:, plan:, limit:)
        orgs = []
        all_org_ids.each do |oid|
          org = Onetime::Organization.load(oid)
          next unless org
          next if owner && !matches_owner?(org, owner)
          next if plan && org.planid != plan

          orgs << org
          break if orgs.size >= limit
        end
        orgs
      end

      def matches_owner?(org, owner)
        owner_email = org.owner&.email&.downcase
        owner_email&.include?(owner.downcase)
      end
    end

    register 'organizations list', OrgListCommand
  end
end
