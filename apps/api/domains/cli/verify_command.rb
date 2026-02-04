# apps/api/domains/cli/verify_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Unified domain verification command
    #
    # Single domain:
    #   bin/ots domains verify example.com
    #   bin/ots domains verify example.com --dry-run
    #   bin/ots domains verify example.com --json
    #
    # Bulk mode:
    #   bin/ots domains verify --all --unverified --limit=10
    #   bin/ots domains verify --all --orphaned --dry-run
    #
    class DomainsVerifyCommand < Command
      include DomainsHelpers

      desc 'Verify domain ownership and SSL status'

      argument :domain_name,
        type: :string,
        required: false,
        desc: 'Domain name to verify (omit for bulk mode with --all)'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Bulk mode: verify multiple domains'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Perform checks without persisting changes'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output results as JSON'

      option :rate_limit,
        type: :float,
        default: 0.5,
        desc: 'Delay between API calls in bulk mode (seconds)'

      # Filter options for bulk mode
      option :orphaned,
        type: :boolean,
        default: false,
        desc: 'Filter for orphaned domains only'

      option :verified,
        type: :boolean,
        default: false,
        desc: 'Filter for already verified domains'

      option :unverified,
        type: :boolean,
        default: false,
        desc: 'Filter for unverified domains'

      option :org_id,
        type: :string,
        default: nil,
        desc: 'Filter by organization ID'

      option :limit,
        type: :integer,
        default: nil,
        desc: 'Maximum number of domains to process'

      def call(domain_name: nil, all: false, dry_run: false, json: false,
               rate_limit: 0.5, orphaned: false, verified: false,
               unverified: false, org_id: nil, limit: nil, **)
        boot_application!

        if all
          verify_bulk(
            dry_run: dry_run,
            json: json,
            rate_limit: rate_limit,
            orphaned: orphaned,
            verified: verified,
            unverified: unverified,
            org_id: org_id,
            limit: limit,
          )
        elsif domain_name
          verify_single(domain_name, dry_run: dry_run, json: json)
        else
          puts 'Error: Provide a domain name or use --all for bulk mode'
          puts 'Usage:'
          puts '  bin/ots domains verify example.com'
          puts '  bin/ots domains verify --all --unverified'
          exit 1
        end
      end

      private

      def verify_single(domain_name, dry_run:, json:)
        domain = load_domain_by_name(domain_name)
        return unless domain

        result = Onetime::Operations::VerifyDomain.new(
          domain: domain,
          persist: !dry_run,
        ).call

        if json
          output_json_single(result, dry_run: dry_run)
        else
          output_human_single(result, dry_run: dry_run)
        end
      end

      def verify_bulk(dry_run:, json:, rate_limit:, orphaned:, verified:,
                      unverified:, org_id:, limit:)
        domains = load_filtered_domains(
          orphaned: orphaned,
          verified: verified,
          unverified: unverified,
          org_id: org_id,
          limit: limit,
        )

        if domains.empty?
          puts 'No domains match the specified filters'
          return
        end

        puts "Processing #{domains.size} domain(s)..." unless json

        result = Onetime::Operations::VerifyDomain.new(
          domains: domains,
          persist: !dry_run,
          rate_limit: rate_limit,
        ).call

        if json
          output_json_bulk(result, dry_run: dry_run)
        else
          output_human_bulk(result, dry_run: dry_run)
        end
      end

      def load_filtered_domains(orphaned:, verified:, unverified:, org_id:, limit:)
        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains    = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        filtered = apply_filters(
          all_domains,
          orphaned: orphaned,
          org_id: org_id,
          verified: verified,
          unverified: unverified,
        )

        # Apply limit if specified
        filtered = filtered.take(limit) if limit

        filtered
      end

      # Human-readable output for single domain
      def output_human_single(result, dry_run:)
        domain = result.domain

        puts '=' * 70
        puts "Domain Verification: #{domain.display_domain}"
        puts '(DRY RUN - no changes persisted)' if dry_run
        puts '=' * 70
        puts

        if result.success?
          puts 'Verification Results:'
          puts "  DNS Validated:    #{format_bool(result.dns_validated)}"
          puts "  SSL Ready:        #{format_bool(result.ssl_ready)}"
          puts "  Is Resolving:     #{format_bool(result.is_resolving)}"
          puts
          puts 'State:'
          puts "  Previous:         #{result.previous_state}"
          puts "  Current:          #{result.current_state}"
          puts "  Changed:          #{result.changed? ? 'yes' : 'no'}"
          puts "  Persisted:        #{result.persisted ? 'yes' : 'no'}"
        else
          puts "ERROR: #{result.error}"
        end
        puts
      end

      # Human-readable output for bulk verification
      def output_human_bulk(result, dry_run:)
        puts
        puts '=' * 70
        puts 'Bulk Verification Summary'
        puts '(DRY RUN - no changes persisted)' if dry_run
        puts '=' * 70
        puts
        puts format('  Total Processed:  %d', result.total)
        puts format('  Verified:         %d', result.verified_count)
        puts format('  Failed:           %d', result.failed_count)
        puts format('  Duration:         %.2f seconds', result.duration_seconds)
        puts

        # Show individual results
        if result.results.any?
          puts 'Results:'
          puts format('%-40s %-12s %-12s %-10s', 'Domain', 'DNS', 'Resolving', 'State')
          puts '-' * 80

          result.results.each do |r|
            status = r.success? ? r.current_state : 'ERROR'
            puts format(
              '%-40s %-12s %-12s %-10s',
              r.domain.display_domain[0..39],
              format_bool(r.dns_validated),
              format_bool(r.is_resolving),
              status,
            )
            puts "  Error: #{r.error}" unless r.success?
          end
        end
        puts
      end

      # JSON output for single domain
      def output_json_single(result, dry_run:)
        output = result.to_h.merge(dry_run: dry_run)
        puts JSON.pretty_generate(output)
      end

      # JSON output for bulk verification
      def output_json_bulk(result, dry_run:)
        output = result.to_h.merge(dry_run: dry_run)
        puts JSON.pretty_generate(output)
      end

      def format_bool(value)
        case value
        when true then 'yes'
        when false then 'no'
        else 'unknown'
        end
      end
    end
  end
end

Onetime::CLI.register 'domains verify', Onetime::CLI::DomainsVerifyCommand
