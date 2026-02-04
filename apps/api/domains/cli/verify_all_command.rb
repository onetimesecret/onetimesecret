# apps/api/domains/cli/verify_all_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'json'

module Onetime
  module CLI
    # Bulk domain verification scan
    class DomainsVerifyAllCommand < Command
      include DomainsHelpers

      desc 'Scan all domains and report verification status'

      option :refresh,
        type: :boolean,
        default: false,
        desc: 'Perform live DNS/SSL checks (rate-limited)'

      option :rate_limit,
        type: :float,
        default: 0.5,
        desc: 'Seconds between API calls when refreshing'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON for scripting'

      option :orphaned,
        type: :boolean,
        default: false,
        desc: 'Filter for orphaned domains only'

      option :verified,
        type: :boolean,
        default: false,
        desc: 'Filter for verified domains only'

      option :unverified,
        type: :boolean,
        default: false,
        desc: 'Filter for unverified domains only'

      option :org_id,
        type: :string,
        default: nil,
        desc: 'Filter by organization ID'

      option :limit,
        type: :integer,
        default: nil,
        desc: 'Maximum number of domains to scan'

      def call(refresh: false, rate_limit: 0.5, json: false, orphaned: false,
               verified: false, unverified: false, org_id: nil, limit: nil, **)
        boot_application!

        strategy         = get_validation_strategy
        all_domains      = load_all_domains
        filtered_domains = apply_filters(
          all_domains,
          orphaned: orphaned,
          org_id: org_id,
          verified: verified,
          unverified: unverified,
        )

        # Apply limit
        filtered_domains = filtered_domains.first(limit.to_i) if limit

        result = scan_domains(filtered_domains, strategy, refresh, rate_limit, json)

        if json
          puts JSON.pretty_generate(result)
        else
          display_scan_result(result, strategy, refresh)
        end
      end

      private

      def load_all_domains
        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact
      end

      def scan_domains(domains, strategy, refresh, rate_limit, json_mode)
        state_counts   = Hash.new(0)
        issues         = { orphaned: [], org_not_found: [], dns_failed: [], ssl_failed: [] }
        domain_details = []

        domains.each_with_index do |domain, idx|
          state                = domain.verification_state.to_s
          state_counts[state] += 1

          detail = analyze_domain(domain, strategy, refresh)
          domain_details << detail

          collect_issues(domain, detail, issues)

          if refresh && strategy.manages_certificates?
            sleep(rate_limit) if idx < domains.size - 1
            print '.' unless json_mode
          end
        end
        puts if refresh && strategy.manages_certificates? && !json_mode

        {
          timestamp: Time.now.utc.iso8601,
          strategy: strategy.strategy_name,
          refresh_mode: refresh,
          total: domains.size,
          state_distribution: state_counts,
          issues: issues.transform_values(&:size),
          issue_details: issues.transform_values { |arr| arr.map { |d| d[:domain] } },
          domains: domain_details,
        }
      end

      def analyze_domain(domain, strategy, refresh)
        detail = {
          domain: domain.display_domain,
          state: domain.verification_state.to_s,
          org_id: domain.org_id.to_s.empty? ? nil : domain.org_id,
          org_status: determine_org_status(domain),
        }

        if refresh && strategy.manages_certificates?
          detail[:live_dns] = perform_dns_check(strategy, domain)
          detail[:live_ssl] = perform_ssl_check(strategy, domain)
        end

        detail
      end

      def determine_org_status(domain)
        if domain.org_id.to_s.empty?
          'orphaned'
        elsif domain.primary_organization
          'ok'
        else
          'not_found'
        end
      end

      def perform_dns_check(strategy, domain)
        result = strategy.validate_ownership(domain)
        { validated: result[:validated], message: result[:message] }
      rescue StandardError => ex
        { validated: false, message: "Error: #{ex.message}" }
      end

      def perform_ssl_check(strategy, domain)
        result = strategy.check_status(domain)
        { ready: result[:ready], status: result[:status] }
      rescue StandardError => ex
        { ready: false, message: "Error: #{ex.message}" }
      end

      def collect_issues(_domain, detail, issues)
        issues[:orphaned] << detail if detail[:org_status] == 'orphaned'
        issues[:org_not_found] << detail if detail[:org_status] == 'not_found'

        if detail[:live_dns] && !detail[:live_dns][:validated]
          issues[:dns_failed] << detail
        end

        if detail[:live_ssl] && !detail[:live_ssl][:ready]
          issues[:ssl_failed] << detail
        end
      end

      def display_scan_result(result, strategy, refresh)
        puts '=' * 80
        puts 'Domain Verification Scan'
        puts '=' * 80
        puts

        puts "Timestamp:          #{result[:timestamp]}"
        puts "Strategy:           #{strategy.strategy_name}"
        puts "Refresh mode:       #{refresh}"
        puts

        display_summary(result)
        display_issues(result)
      end

      def display_summary(result)
        puts 'Summary:'
        puts "  Total domains:    #{result[:total]}"
        puts

        total = result[:total].to_f
        total = 1.0 if total.zero?

        puts '  State Distribution:'
        %w[verified resolving pending unverified].each do |state|
          count = result[:state_distribution][state] || 0
          pct   = (count / total * 100).round(1)
          puts format('    %-16s %3d (%5.1f%%)', state, count, pct)
        end
        puts
      end

      def display_issues(result)
        puts 'Issues Detected:'
        issues = result[:issues]
        puts "  Orphaned:         #{issues[:orphaned]}"
        puts "  Org not found:    #{issues[:org_not_found]}"

        if issues[:dns_failed]&.positive?
          puts "  DNS failures:     #{issues[:dns_failed]}"
        end

        if issues[:ssl_failed]&.positive?
          puts "  SSL failures:     #{issues[:ssl_failed]}"
        end
        puts

        # Show first few issue domains
        details = result[:issue_details]
        show_issue_domains('Orphaned domains', details[:orphaned])
        show_issue_domains('Org not found', details[:org_not_found])
        show_issue_domains('DNS failures', details[:dns_failed]) if details[:dns_failed]&.any?
        show_issue_domains('SSL failures', details[:ssl_failed]) if details[:ssl_failed]&.any?
      end

      def show_issue_domains(label, domains)
        return if domains.nil? || domains.empty?

        puts "#{label}:"
        domains.first(5).each { |d| puts "  - #{d}" }
        puts "  ... and #{domains.size - 5} more" if domains.size > 5
        puts
      end
    end
  end
end

Onetime::CLI.register 'domains verify-all', Onetime::CLI::DomainsVerifyAllCommand
