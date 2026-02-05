# apps/api/domains/cli/verify_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/verify_domain'
require 'json'

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
        desc: 'Perform checks without persisting changes (read-only health check)'

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
          puts '  bin/ots domains verify example.com --dry-run  # read-only check'
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

      # Load all domains using pipelining to avoid N+1 queries
      #
      # @return [Array<CustomDomain>] All domain objects
      def load_all_domains
        all_domain_ids = Onetime::CustomDomain.instances.all
        return [] if all_domain_ids.empty?

        # Use Familia's batch loading (pipelined HGETALL internally)
        Onetime::CustomDomain.load_multi(all_domain_ids).compact
      end

      def load_filtered_domains(orphaned:, verified:, unverified:, org_id:, limit:)
        all_domains = load_all_domains

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
          output_verification_results(result, domain)
          output_state_info(result)
          output_organization_info(domain) if dry_run
          output_brand_info(domain) if dry_run
          output_diagnostic_commands(result, domain)
        else
          puts "ERROR: #{result.error}"
        end
        puts
      end

      def output_verification_results(result, _domain)
        puts 'Verification Results:'
        puts "  DNS Validated:    #{format_bool(result.dns_validated)}"
        puts "  SSL Ready:        #{format_bool(result.ssl_ready)}"
        puts "  Is Resolving:     #{format_bool(result.is_resolving)}"
        puts
      end

      def output_state_info(result)
        puts 'State:'
        puts "  Previous:         #{result.previous_state}"
        puts "  Current:          #{result.current_state}"
        puts "  Changed:          #{result.changed? ? 'yes' : 'no'}"
        puts "  Persisted:        #{result.persisted ? 'yes' : 'no'}"
        puts
      end

      def output_organization_info(domain)
        puts 'Organization:'
        if domain.org_id.to_s.empty?
          puts '  Status:           ORPHANED'
        else
          org = domain.primary_organization
          if org
            puts '  Status:           OK'
            puts "  Org ID:           #{org.org_id}"
            puts "  Display Name:     #{org.display_name || org.org_id}"
          else
            puts '  Status:           ORG_NOT_FOUND'
            puts "  Org ID:           #{domain.org_id} (MISSING)"
          end
        end
        puts
      end

      def output_brand_info(domain)
        puts 'Brand Settings:'
        puts "  Public Homepage:  #{domain.allow_public_homepage?}"
        puts "  Public API:       #{domain.allow_public_api?}"
        puts
      end

      def output_diagnostic_commands(result, domain)
        puts 'Manual Verification Commands:'
        puts '-' * 70

        # DNS ownership validation
        txt_host  = domain.txt_validation_host
        txt_value = domain.txt_validation_value
        if txt_host && txt_value
          full_txt_host = "#{txt_host}.#{domain.base_domain}"
          puts
          puts '1. DNS Ownership (TXT record):'
          puts "   Status: #{result.dns_validated ? 'PASS' : 'FAIL'}"
          puts "   Expected: TXT record at #{full_txt_host}"
          puts "   Value:    #{txt_value}"
          puts
          puts '   # Check TXT record:'
          puts "   dig TXT #{full_txt_host} +short"
          puts
        else
          puts
          puts '1. DNS Ownership: No TXT validation configured for this domain'
          puts
        end

        # CNAME/A record resolution
        puts '2. DNS Resolution (CNAME/A record):'
        puts "   Status: #{result.is_resolving ? 'PASS' : 'FAIL'}"
        puts '   Domain should resolve to the proxy server'
        puts
        puts '   # Check CNAME record:'
        puts "   dig CNAME #{domain.display_domain} +short"
        puts
        puts '   # Check A record (if no CNAME):'
        puts "   dig A #{domain.display_domain} +short"
        puts

        # SSL certificate
        puts '3. SSL Certificate:'
        puts "   Status: #{result.ssl_ready ? 'PASS' : 'PENDING'}"
        puts
        puts '   # Check SSL certificate:'
        puts "   echo | openssl s_client -connect #{domain.display_domain}:443 -servername #{domain.display_domain} 2>/dev/null | openssl x509 -noout -dates"
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

        # Show state distribution
        output_state_distribution(result)

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

      def output_state_distribution(result)
        state_counts = Hash.new(0)
        result.results.each do |r|
          state                = r.current_state.to_s
          state_counts[state] += 1
        end

        total = result.total.to_f
        total = 1.0 if total.zero?

        puts 'State Distribution:'
        %w[verified resolving pending unverified].each do |state|
          count = state_counts[state] || 0
          pct   = (count / total * 100).round(1)
          puts format('  %-16s %3d (%5.1f%%)', state, count, pct)
        end
        puts
      end

      # JSON output for single domain
      def output_json_single(result, dry_run:)
        domain = result.domain
        output = result.to_h.merge(
          dry_run: dry_run,
          timestamp: Time.now.utc.iso8601,
        )

        # Add extended info for dry-run mode (health check mode)
        if dry_run
          output[:organization] = build_organization_json(domain)
          output[:brand]        = {
            allow_public_homepage: domain.allow_public_homepage?,
            allow_public_api: domain.allow_public_api?,
          }
        end

        puts JSON.pretty_generate(output)
      end

      # JSON output for bulk verification
      def output_json_bulk(result, dry_run:)
        # Build state distribution
        state_counts = Hash.new(0)
        result.results.each do |r|
          state                = r.current_state.to_s
          state_counts[state] += 1
        end

        # Build issues summary
        issues = { orphaned: [], org_not_found: [], dns_failed: [], ssl_failed: [] }
        result.results.each do |r|
          domain = r.domain
          issues[:orphaned] << domain.display_domain if domain.org_id.to_s.empty?
          if !domain.org_id.to_s.empty? && domain.primary_organization.nil?
            issues[:org_not_found] << domain.display_domain
          end
          issues[:dns_failed] << domain.display_domain unless r.dns_validated
          issues[:ssl_failed] << domain.display_domain unless r.ssl_ready
        end

        output = result.to_h.merge(
          dry_run: dry_run,
          timestamp: Time.now.utc.iso8601,
          state_distribution: state_counts,
          issues: issues.transform_values(&:size),
          issue_details: issues,
        )

        puts JSON.pretty_generate(output)
      end

      def build_organization_json(domain)
        if domain.org_id.to_s.empty?
          { status: 'ORPHANED', org_id: nil, display_name: nil }
        else
          org = domain.primary_organization
          if org
            {
              status: 'OK',
              org_id: org.org_id,
              display_name: org.display_name || org.org_id,
            }
          else
            { status: 'ORG_NOT_FOUND', org_id: domain.org_id, display_name: nil }
          end
        end
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
