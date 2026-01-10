# apps/api/domains/cli/bulk_repair_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Bulk repair domains
    class DomainsBulkRepairCommand < Command
      include DomainsHelpers

      desc 'Find and fix all domain relationship issues'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview changes without applying'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompt'

      def call(dry_run: false, force: false, **)
        boot_application!

        puts 'Scanning for domain relationship issues...'
        puts

        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains    = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        orphaned_domains   = []
        mismatched_domains = []

        all_domains.each do |domain|
          if domain.org_id.to_s.empty?
            orphaned_domains << domain
          else
            org = load_organization(domain.org_id, silent: true)
            if org
              domains_in_org = org.list_domains
              unless domains_in_org.include?(domain.domainid)
                mismatched_domains << [domain, org]
              end
            end
          end
        end

        puts 'Scan Results:'
        puts "  Total domains:        #{all_domains.size}"
        puts "  Orphaned domains:     #{orphaned_domains.size}"
        puts "  Mismatched domains:   #{mismatched_domains.size}"
        puts

        if orphaned_domains.empty? && mismatched_domains.empty?
          puts 'No issues found - all domain relationships are consistent'
          return
        end

        # Show orphaned domains
        if orphaned_domains.any?
          puts 'Orphaned Domains (no org_id):'
          orphaned_domains.first(10).each do |domain|
            puts "  - #{domain.display_domain}"
          end
          puts "  ... and #{orphaned_domains.size - 10} more" if orphaned_domains.size > 10
          puts
        end

        # Show mismatched domains
        if mismatched_domains.any?
          puts 'Mismatched Domains (org_id set but not in organization collection):'
          mismatched_domains.first(10).each do |domain, org|
            puts "  - #{domain.display_domain} (org: #{org.org_id})"
          end
          puts "  ... and #{mismatched_domains.size - 10} more" if mismatched_domains.size > 10
          puts
        end

        if dry_run
          puts 'Dry run - no changes made'
          puts
          puts 'To apply repairs: ots domains bulk-repair [--force]'
          return
        end

        unless force
          print "Repair #{mismatched_domains.size} mismatched domains? (Note: Orphaned domains require manual assignment) [y/N]: "
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Repair mismatched domains
        repaired = 0
        failed   = 0

        mismatched_domains.each do |domain, org|
            org.add_domain(domain.domainid)
            domain.updated = OT.now.to_i
            domain.save
            repaired      += 1
            print '.'
        rescue StandardError => ex
            failed += 1
            print 'F'
            OT.le "[CLI] Failed to repair #{domain.display_domain}: #{ex.message}"
        end

        puts
        puts
        puts 'Bulk Repair Summary:'
        puts "  Repaired:             #{repaired}"
        puts "  Failed:               #{failed}"
        puts "  Orphaned (skipped):   #{orphaned_domains.size}"
        puts
        puts 'Note: Orphaned domains require manual assignment with:'
        puts '  ots domains repair <domain> --org-id=<org-id>'
      end
    end
  end
end

Onetime::CLI.register 'domains bulk-repair', Onetime::CLI::DomainsBulkRepairCommand
