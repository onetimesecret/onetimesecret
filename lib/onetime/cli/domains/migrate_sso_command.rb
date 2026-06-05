# lib/onetime/cli/domains/migrate_sso_command.rb
#
# frozen_string_literal: true

# Bulk-migrate legacy install-level SSO users into a domain organization.
#
# When a customer switches from install-level SSO to domain-level SSO,
# users who previously signed in retain independent accounts with personal
# workspaces. This command migrates them into the domain's organization.
#
# Usage:
#   bin/ots domains migrate-sso secrets.example.com              # Dry run
#   bin/ots domains migrate-sso secrets.example.com --run        # Execute
#   bin/ots domains migrate-sso secrets.example.com --run -v     # Verbose
#
# @see https://github.com/onetimesecret/onetimesecret/issues/3335

require 'json'

module Onetime
  module CLI
    class DomainsMigrateSsoCommand < Command
      desc 'Bulk-migrate legacy install-level SSO users into a domain organization'

      argument :fqdn,
        type: :string,
        required: true,
        desc: 'Domain FQDN (e.g., secrets.example.com)'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute changes (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each account'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(fqdn:, run: false, verbose: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!
        require_relative '../../../../apps/web/auth/operations/bulk_sso_migration'
        require_relative '../../../../apps/web/auth/operations/join_domain_organization'

        domain = Onetime::CustomDomain.load_by_display_domain(fqdn)
        unless domain
          $stderr.puts "Domain not found: #{fqdn}"
          exit 1
        end

        dry_run   = !run
        migration = Auth::Operations::BulkSsoMigration.new(domain: domain, dry_run: dry_run)

        unless json
          puts "\nBulk SSO Migration"
          puts '=' * 60
          puts "  Domain:       #{domain.display_domain}"
          puts "  Base domain:  #{domain.base_domain}"
          puts "  Organization: #{migration.organization.display_name} (#{migration.organization.extid})"
          puts "  Mode:         #{dry_run ? 'DRY RUN' : 'LIVE'}"
        end

        candidates = scan_candidates(migration, json)
        if candidates.empty?
          finish_empty(domain, json)
          return
        end

        stats   = { total: 0, migrated: 0, skipped: 0, archive_warnings: 0, errors: [] }
        results = []

        candidates.each_with_index do |customer, idx|
          stats[:total] += 1
          label = "[#{idx + 1}/#{candidates.size}]"

          result = migration.migrate_customer(customer)
          results << result
          update_stats(stats, result)
          report_result(result, label, verbose) unless json
        rescue StandardError => ex
          stats[:errors] << "#{customer.extid}: #{ex.message}"
          puts "  #{label} Error: #{ex.message}" unless json
        end

        if json
          output_json(domain, migration, stats, results, dry_run)
        else
          print_results(stats, dry_run)
          print_next_steps(dry_run, stats[:migrated]) if dry_run
        end
      end

      private

      def scan_candidates(migration, json)
        puts "\nScanning for eligible users..." unless json

        candidates = migration.find_eligible_customers do |scanned, total|
          next if json

          print "\r  Scanned #{scanned}/#{total} customers..." if total >= 100
        end
        print "\r" + (' ' * 60) + "\r" unless json

        unless json
          if candidates.empty?
            puts "\nNo eligible users found."
          else
            puts "\nFound #{candidates.size} eligible user(s)"
          end
        end

        candidates
      end

      def finish_empty(domain, json)
        if json
          puts JSON.pretty_generate({
            domain: domain.display_domain,
            eligible: 0,
            message: 'No eligible users found',
          })
        end
      end

      def update_stats(stats, result)
        case result.status
        when :migrated, :would_migrate      then stats[:migrated] += 1
        when :migrated_archive_failed       then stats[:migrated] += 1; stats[:archive_warnings] += 1
        when :skipped_already_member        then stats[:skipped] += 1
        when :error                         then stats[:errors] << "#{result.customer_extid}: #{result.message}"
        end
      end

      def report_result(result, label, verbose)
        return unless verbose

        message = case result.status
                  when :would_migrate
                    "Would migrate: #{result.email_obscured} -> #{result.organization_extid}"
                  when :migrated
                    "Migrated: #{result.email_obscured} -> #{result.organization_extid}"
                  when :migrated_archive_failed
                    "Migrated (archive failed): #{result.email_obscured} -> #{result.organization_extid}"
                  when :skipped_already_member
                    "Skipped: #{result.email_obscured} (already member)"
                  when :error
                    "Error: #{result.email_obscured} (#{result.message})"
                  end

        personal = result.personal_org_extid ? " [personal: #{result.personal_org_extid}]" : ''
        puts "  #{label} #{message}#{personal}" if message
      end

      def print_results(stats, dry_run)
        puts "\n" + ('=' * 60)
        puts "Migration #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total eligible:'.ljust(35) + stats[:total].to_s
        puts "  #{dry_run ? 'Would migrate' : 'Migrated'}:".ljust(35) + stats[:migrated].to_s
        puts '  Skipped (already member):'.ljust(35) + stats[:skipped].to_s
        puts '  Archive warnings:'.ljust(35) + stats[:archive_warnings].to_s if stats[:archive_warnings] > 0

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(35) + stats[:errors].size.to_s
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, migrated_count)
        return unless dry_run && migrated_count > 0

        puts <<~MESSAGE

          To execute, run with --run
        MESSAGE
      end

      def output_json(domain, migration, stats, results, dry_run)
        puts JSON.pretty_generate({
          domain: domain.display_domain,
          organization: migration.organization.extid,
          dry_run: dry_run,
          statistics: {
            total: stats[:total],
            migrated: stats[:migrated],
            skipped: stats[:skipped],
            archive_warnings: stats[:archive_warnings],
            errors: stats[:errors].size,
          },
          results: results.map { |r|
            {
              status: r.status,
              customer: r.customer_extid,
              email: r.email_obscured,
              organization: r.organization_extid,
              personal_workspace: r.personal_org_extid,
              message: r.message,
            }
          },
        })
      end

      def show_usage_help
        puts <<~USAGE

          Bulk SSO Migration

          Usage:
            bin/ots domains migrate-sso FQDN [options]

          Description:
            Migrates legacy install-level SSO users into a domain's organization.

            When a customer switches from install-level SSO to domain-level SSO,
            users who previously signed in retain independent accounts with personal
            default workspaces. This command finds those users (by email domain match)
            and migrates them into the domain's organization.

            For each eligible user:
              1. Joins the domain organization (reuses SSO join logic)
              2. Sets default_org_id to the domain organization
              3. Soft-archives the personal workspace (preserves all data)

          Arguments:
            FQDN                    Domain FQDN (e.g., secrets.example.com)

          Options:
            --run                   Execute changes (default is dry-run)
            --verbose, -v           Show detailed progress for each account
            --json                  JSON output (for scripting)
            --help, -h              Show this help message

          Examples:
            # Preview (dry run)
            bin/ots domains migrate-sso secrets.example.com

            # Execute migration
            bin/ots domains migrate-sso secrets.example.com --run

            # Execute with verbose output
            bin/ots domains migrate-sso secrets.example.com --run --verbose

            # JSON output for scripting
            bin/ots domains migrate-sso secrets.example.com --json

          Safety:
            - Default mode is dry-run (no changes)
            - Idempotent: safe to run multiple times
            - Personal workspaces are soft-archived (data preserved)
            - Each action is logged with customer extid

        USAGE
        true
      end
    end

    register 'domains migrate-sso', DomainsMigrateSsoCommand
  end
end
