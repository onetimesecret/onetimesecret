# lib/onetime/cli/domains_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Base module for domain command helpers
    module DomainsHelpers
      def apply_filters(domains, orphaned: false, org_id: nil, verified: false, unverified: false)
        filtered = domains

        # Filter by orphaned status
        if orphaned
          filtered = filtered.select { |d| d.org_id.to_s.empty? }
        end

        # Filter by organization
        if org_id
          filtered = filtered.select { |d| d.org_id.to_s == org_id.to_s }
        end

        # Filter by verification status
        if verified
          filtered = filtered.select { |d| d.verified.to_s == 'true' }
        elsif unverified
          filtered = filtered.select { |d| d.verified.to_s != 'true' }
        end

        filtered
      end

      def format_domain_row(domain)
        org_info = get_organization_info(domain)
        status = domain.verification_state || 'unknown'
        verified = domain.verified.to_s == 'true' ? 'yes' : 'no'

        format('%-40s %-30s %-12s %-10s',
               domain.display_domain[0..39],
               org_info[0..29],
               status[0..11],
               verified)
      end

      def get_organization_info(domain)
        if domain.org_id.to_s.empty?
          'ORPHANED'
        else
          org = domain.primary_organization
          if org
            "#{org.display_name || org.org_id}"
          else
            "ORG NOT FOUND (#{domain.org_id[0..10]})"
          end
        end
      end

      def load_domain_by_name(domain_name)
        domain = Onetime::CustomDomain.load_by_display_domain(domain_name)
        unless domain
          puts "Error: Domain '#{domain_name}' not found"
          return nil
        end
        domain
      end

      def load_organization(org_id, silent: false)
        org = Onetime::Organization.load(org_id)
        unless org
          puts "Error: Organization '#{org_id}' not found" unless silent
          return nil
        end
        org
      end

      def format_timestamp(timestamp)
        return 'N/A' unless timestamp
        Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S UTC')
      rescue StandardError
        'invalid'
      end
    end

    # Main domains command (list all)
    class DomainsCommand < Command
      include DomainsHelpers

      desc 'List all custom domains with organization info'

      option :orphaned, type: :boolean, default: false,
             desc: 'Filter for orphaned domains only'

      option :org_id, type: :string, default: nil,
             desc: 'Filter by organization ID'

      option :verified, type: :boolean, default: false,
             desc: 'Filter for verified domains only'

      option :unverified, type: :boolean, default: false,
             desc: 'Filter for unverified domains only'

      def call(orphaned: false, org_id: nil, verified: false, unverified: false, **)
        boot_application!

        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        # Apply filters
        filtered_domains = apply_filters(all_domains, orphaned: orphaned, org_id: org_id,
                                         verified: verified, unverified: unverified)

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
            puts format('%-40s %-30s %-12s %-10s',
                       "#{display_domain} (#{domains.size} records)",
                       'DUPLICATES',
                       'CHECK',
                       '?')
            domains.each_with_index do |domain, idx|
              org_info = get_organization_info(domain)
              puts format('  [%d] %-37s %-30s', idx + 1, domain.domainid[0..36], org_info)
            end
          end
        end
      end
    end

    # Domain info subcommand
    class DomainsInfoCommand < Command
      include DomainsHelpers

      desc 'Show detailed information about a domain'

      argument :domain_name, type: :string, required: true, desc: 'Domain name'

      def call(domain_name:, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        puts '=' * 80
        puts "Domain Information: #{domain_name}"
        puts '=' * 80
        puts

        # Basic domain info
        puts 'Domain Details:'
        puts "  Display Domain:       #{domain.display_domain}"
        puts "  Base Domain:          #{domain.base_domain || 'N/A'}"
        puts "  Subdomain:            #{domain.subdomain || 'N/A'}"
        puts "  TLD:                  #{domain.tld || 'N/A'}"
        puts "  SLD:                  #{domain.sld || 'N/A'}"
        puts "  TRD:                  #{domain.trd || 'N/A'}"
        puts

        # Organization ownership
        puts 'Organization Ownership:'
        if domain.org_id.to_s.empty?
          puts '  Status:               ORPHANED (no organization)'
        else
          org = domain.primary_organization
          if org
            owner = org.owner
            puts "  Organization:         #{org.display_name || 'N/A'} (#{org.org_id})"
            puts "  Organization ID:      #{domain.org_id}"
            puts "  Owner Email:          #{owner ? owner.email : 'N/A'}"
            puts "  Member Count:         #{org.member_count}"
          else
            puts "  Organization ID:      #{domain.org_id}"
            puts '  Status:               ORG NOT FOUND (orphaned reference)'
          end
        end
        puts

        # Verification status
        puts 'Verification:'
        puts "  Verified:             #{domain.verified || 'false'}"
        puts "  Resolving:            #{domain.resolving || 'false'}"
        puts "  Verification State:   #{domain.verification_state}"
        puts "  Status:               #{domain.status || 'N/A'}"
        puts

        # DNS records
        puts 'DNS Configuration:'
        puts "  TXT Validation Host:  #{domain.txt_validation_host || 'N/A'}"
        puts "  TXT Validation Value: #{domain.txt_validation_value || 'N/A'}"
        puts "  Validation Record:    #{domain.validation_record || 'N/A'}"
        puts

        # Vhost configuration
        puts 'Configuration:'
        puts "  Vhost:                #{domain.vhost || 'N/A'}"
        puts "  Allow Public Home:    #{domain.allow_public_homepage? || 'false'}"
        puts "  Allow Public API:     #{domain.allow_public_api? || 'false'}"
        puts "  Apex Domain:          #{domain.apex? || 'false'}"
        puts

        # Timestamps
        puts 'Timestamps:'
        puts "  Created:              #{format_timestamp(domain.created)}"
        puts "  Updated:              #{format_timestamp(domain.updated)}"
        puts

        # Internal identifiers
        puts 'Internal:'
        puts "  Object ID (objid):    #{domain.objid}"
        puts "  External ID (extid):  #{domain.extid}"
        puts "  Domain ID:            #{domain.domainid}"
        puts "  DB Key:               #{domain.dbkey}"
        puts
      end
    end

    # List orphaned domains
    class DomainsOrphanedCommand < Command
      include DomainsHelpers

      desc 'List domains without organization ownership'

      def call(**)
        boot_application!

        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        orphaned_domains = all_domains.select { |d| d.org_id.to_s.empty? }

        puts "#{orphaned_domains.size} orphaned custom domains found"
        return if orphaned_domains.empty?

        puts
        puts format('%-40s %-12s %-10s %-20s', 'Domain', 'Status', 'Verified', 'Created')
        puts '-' * 85

        orphaned_domains.sort_by(&:display_domain).each do |domain|
          status = domain.verification_state || 'unknown'
          verified = domain.verified || 'false'
          created = format_timestamp(domain.created)

          puts format('%-40s %-12s %-10s %-20s',
                     domain.display_domain,
                     status,
                     verified,
                     created)
        end
      end
    end

    # Transfer domain
    class DomainsTransferCommand < Command
      include DomainsHelpers

      desc 'Transfer domain between organizations'

      argument :domain_name, type: :string, required: true, desc: 'Domain name'

      option :to_org, type: :string, required: true,
             desc: 'Destination organization ID'

      option :from_org, type: :string, default: nil,
             desc: 'Source organization ID (optional, uses domain\'s current org_id)'

      option :force, type: :boolean, default: false,
             desc: 'Skip confirmation prompt'

      def call(domain_name:, to_org:, from_org: nil, force: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        from_org_id = from_org || domain.org_id

        # Load organizations
        to_org_obj = load_organization(to_org)
        return unless to_org_obj

        from_org_obj = nil
        if from_org_id.to_s.empty?
          puts 'Note: Domain is currently orphaned (no organization)'
        else
          from_org_obj = load_organization(from_org_id)
          return unless from_org_obj

          # Verify current ownership
          unless domain.org_id.to_s == from_org_id.to_s
            puts "Error: Domain org_id (#{domain.org_id}) does not match --from-org (#{from_org_id})"
            return
          end
        end

        # Display transfer details
        puts 'Transfer Details:'
        puts "  Domain:               #{domain_name}"
        if from_org_obj
          puts "  From Organization:    #{from_org_obj.display_name || 'N/A'} (#{from_org_obj.org_id})"
        else
          puts '  From Organization:    ORPHANED'
        end
        puts "  To Organization:      #{to_org_obj.display_name || 'N/A'} (#{to_org_obj.org_id})"
        puts

        unless force
          print 'Confirm transfer? [y/N]: '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Perform transfer
        begin
          # Remove from old organization's collection if exists
          if from_org_obj
            from_org_obj.remove_domain(domain.domainid)
            puts "  Removed from #{from_org_obj.display_name || from_org_obj.org_id}"
          end

          # Update domain's org_id
          domain.org_id = to_org
          domain.updated = OT.now.to_i
          domain.save

          # Add to new organization's collection
          to_org_obj.add_domain(domain.domainid)
          puts "  Added to #{to_org_obj.display_name || to_org_obj.org_id}"
          puts "  Updated org_id field"

          OT.info "[CLI] Domain transfer: #{domain_name} from #{from_org_id || 'orphaned'} to #{to_org}"
          puts
          puts 'Transfer complete'
        rescue StandardError => ex
          puts "Error during transfer: #{ex.message}"
          OT.le "[CLI] Domain transfer failed: #{ex.message}"
        end
      end
    end

    # Repair domain
    class DomainsRepairCommand < Command
      include DomainsHelpers

      desc 'Fix domain relationship issues'

      argument :domain_name, type: :string, required: true, desc: 'Domain name'

      option :org_id, type: :string, default: nil,
             desc: 'Organization ID to assign if domain is orphaned'

      option :force, type: :boolean, default: false,
             desc: 'Skip confirmation prompt'

      def call(domain_name:, org_id: nil, force: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        puts "Checking domain: #{domain_name}"
        puts

        issues_found = []
        repairs = []

        # Check 1: Orphaned domain
        if domain.org_id.to_s.empty?
          if org_id
            issues_found << 'Domain is orphaned (no org_id)'
            repairs << lambda {
              domain.org_id = org_id
              domain.updated = OT.now.to_i
              domain.save
              org = load_organization(org_id)
              org.add_domain(domain.domainid) if org
              "Assigned to organization #{org_id}"
            }
          else
            puts 'Issue: Domain is orphaned (no org_id)'
            puts 'Fix: Provide --org-id=<id> to assign to an organization'
            return
          end
        else
          # Check 2: org_id set but not in organization's collection
          org = load_organization(domain.org_id)
          if org
            domains_in_org = org.list_domains
            unless domains_in_org.include?(domain.domainid)
              issues_found << "org_id is #{domain.org_id} but not in organization's domains collection"
              repairs << lambda {
                org.add_domain(domain.domainid)
                "Added to organization #{domain.org_id} collection"
              }
            end
          else
            issues_found << "org_id is #{domain.org_id} but organization not found"
            puts "Issue: org_id is #{domain.org_id} but organization not found"
            puts 'Fix: Provide --org-id=<id> to assign to a valid organization'
            return
          end
        end

        if issues_found.empty?
          puts 'No issues found - domain relationships are consistent'
          return
        end

        puts 'Issues Found:'
        issues_found.each_with_index do |issue, idx|
          puts "  #{idx + 1}. #{issue}"
        end
        puts

        unless force
          print 'Apply repairs? [y/N]: '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        puts 'Applying repairs:'
        repairs.each do |repair|
          result = repair.call
          puts "  #{result}"
        end

        OT.info "[CLI] Domain repair: #{domain_name} - #{issues_found.size} issues fixed"
        puts
        puts 'Repair complete'
      end
    end

    # Bulk repair domains
    class DomainsBulkRepairCommand < Command
      include DomainsHelpers

      desc 'Find and fix all domain relationship issues'

      option :dry_run, type: :boolean, default: false,
             desc: 'Preview changes without applying'

      option :force, type: :boolean, default: false,
             desc: 'Skip confirmation prompt'

      def call(dry_run: false, force: false, **)
        boot_application!

        puts 'Scanning for domain relationship issues...'
        puts

        all_domain_ids = Onetime::CustomDomain.instances.all
        all_domains = all_domain_ids.map do |did|
          Onetime::CustomDomain.find_by_identifier(did)
        end.compact

        orphaned_domains = []
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
        failed = 0

        mismatched_domains.each do |domain, org|
          begin
            org.add_domain(domain.domainid)
            domain.updated = OT.now.to_i
            domain.save
            repaired += 1
            print '.'
          rescue StandardError => ex
            failed += 1
            print 'F'
            OT.le "[CLI] Failed to repair #{domain.display_domain}: #{ex.message}"
          end
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

    # Register all domain commands
    register 'domains', DomainsCommand
    register 'domains info', DomainsInfoCommand
    register 'domains orphaned', DomainsOrphanedCommand
    register 'domains transfer', DomainsTransferCommand
    register 'domains repair', DomainsRepairCommand
    register 'domains bulk-repair', DomainsBulkRepairCommand
  end
end
