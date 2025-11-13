# lib/onetime/cli/domains_command.rb
#
# frozen_string_literal: true

module Onetime
  class DomainsCommand < Onetime::CLI
    def domains
      subcommand = argv.first

      case subcommand
      when 'info', 'domain-info'
        argv.shift
        domain_info
      when 'list-orphaned', 'orphaned'
        argv.shift
        list_orphaned
      when 'transfer'
        argv.shift
        transfer_domain
      when 'repair'
        argv.shift
        repair_domain
      when 'bulk-repair'
        argv.shift
        bulk_repair
      when nil
        # Default behavior - list all domains
        list_all_domains
      else
        # If first arg looks like a domain name, show info
        if subcommand =~ /\A[\w\-]+\.[\w\-.]+\z/
          argv.shift
          domain_info(subcommand)
        else
          show_help
        end
      end
    end

    def revalidate_domains
      domains_to_process = get_domains_to_process
      return unless domains_to_process

      total = domains_to_process.size
      puts "Processing #{total} domain#{'s' unless total == 1}"

      process_domains_in_batches(domains_to_process)

      puts "\nRevalidation complete"
    end

    private

    # Show command help
    def show_help
      puts 'Domain Management'
      puts 'Usage: ots domains [subcommand] [options]'
      puts
      puts 'Subcommands:'
      puts '  (default)              - List all domains with organization info'
      puts '  info <domain>          - Show detailed domain information'
      puts '  list-orphaned          - List domains without organization ownership'
      puts '  transfer <domain>      - Transfer domain between organizations'
      puts '  repair <domain>        - Fix domain relationship issues'
      puts '  bulk-repair            - Find and fix all relationship issues'
      puts
      puts 'Options:'
      puts '  --list                 - List all domains (default behavior)'
      puts '  --orphaned             - Filter for orphaned domains only'
      puts '  --org-id=ID            - Filter by organization ID'
      puts '  --verified             - Filter for verified domains only'
      puts '  --unverified           - Filter for unverified domains only'
      puts '  --from-org=ID          - Source organization for transfer'
      puts '  --to-org=ID            - Destination organization for transfer'
      puts '  --force                - Skip confirmations'
      puts '  --dry-run              - Preview changes without applying'
      puts
      puts 'Examples:'
      puts '  ots domains                           # List all domains'
      puts '  ots domains --orphaned                # List orphaned domains'
      puts '  ots domains info example.com          # Show domain details'
      puts '  ots domains list-orphaned             # List orphaned domains'
      puts '  ots domains transfer example.com --to-org=org_xyz789'
      puts '  ots domains repair example.com        # Fix relationship issues'
      puts '  ots domains bulk-repair --dry-run     # Preview bulk fixes'
    end

    # List all domains with organization info
    def list_all_domains
      all_domain_ids = Onetime::CustomDomain.instances.all
      all_domains = all_domain_ids.map do |did|
        Onetime::CustomDomain.find_by_identifier(did)
      end.compact

      # Apply filters
      filtered_domains = apply_filters(all_domains)

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

    # Show detailed domain information
    def domain_info(domain_name = nil)
      domain_name ||= argv.first
      unless domain_name
        puts 'Error: Domain name required'
        puts 'Usage: ots domains info <domain-name>'
        return
      end

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

    # List orphaned domains
    def list_orphaned
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

    # Transfer domain between organizations
    def transfer_domain(domain_name = nil)
      domain_name ||= argv.first
      unless domain_name
        puts 'Error: Domain name required'
        puts 'Usage: ots domains transfer <domain-name> --to-org=org_xyz789 [--from-org=org_abc123]'
        return
      end

      to_org_id = option.to_org
      unless to_org_id
        puts 'Error: Destination organization required (--to-org=ID)'
        return
      end

      domain = load_domain_by_name(domain_name)
      return unless domain

      from_org_id = option.from_org || domain.org_id

      # Load organizations
      to_org = load_organization(to_org_id)
      return unless to_org

      from_org = nil
      if from_org_id.to_s.empty?
        puts 'Note: Domain is currently orphaned (no organization)'
      else
        from_org = load_organization(from_org_id)
        return unless from_org

        # Verify current ownership
        unless domain.org_id.to_s == from_org_id.to_s
          puts "Error: Domain org_id (#{domain.org_id}) does not match --from-org (#{from_org_id})"
          return
        end
      end

      # Display transfer details
      puts 'Transfer Details:'
      puts "  Domain:               #{domain_name}"
      if from_org
        puts "  From Organization:    #{from_org.display_name || 'N/A'} (#{from_org.org_id})"
      else
        puts '  From Organization:    ORPHANED'
      end
      puts "  To Organization:      #{to_org.display_name || 'N/A'} (#{to_org.org_id})"
      puts

      unless option.force
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
        if from_org
          from_org.remove_domain(domain.domainid)
          puts "  Removed from #{from_org.display_name || from_org.org_id}"
        end

        # Update domain's org_id
        domain.org_id = to_org_id
        domain.updated = OT.now.to_i
        domain.save

        # Add to new organization's collection
        to_org.add_domain(domain.domainid)
        puts "  Added to #{to_org.display_name || to_org.org_id}"
        puts "  Updated org_id field"

        OT.info "[CLI] Domain transfer: #{domain_name} from #{from_org_id || 'orphaned'} to #{to_org_id}"
        puts
        puts 'Transfer complete'
      rescue StandardError => ex
        puts "Error during transfer: #{ex.message}"
        OT.le "[CLI] Domain transfer failed: #{ex.message}"
        warn ex.backtrace if option.verbose
      end
    end

    # Repair domain relationship issues
    def repair_domain(domain_name = nil)
      domain_name ||= argv.first
      unless domain_name
        puts 'Error: Domain name required'
        puts 'Usage: ots domains repair <domain-name> [--org-id=org_abc123]'
        return
      end

      domain = load_domain_by_name(domain_name)
      return unless domain

      puts "Checking domain: #{domain_name}"
      puts

      issues_found = []
      repairs = []

      # Check 1: Orphaned domain
      if domain.org_id.to_s.empty?
        if option.org_id
          issues_found << 'Domain is orphaned (no org_id)'
          repairs << lambda {
            domain.org_id = option.org_id
            domain.updated = OT.now.to_i
            domain.save
            org = load_organization(option.org_id)
            org.add_domain(domain.domainid) if org
            "Assigned to organization #{option.org_id}"
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

      unless option.force
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

    # Bulk repair all domains
    def bulk_repair
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

      if option.dry_run
        puts 'Dry run - no changes made'
        puts
        puts 'To apply repairs: ots domains bulk-repair [--force]'
        return
      end

      unless option.force
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

    # Helper: Apply filters to domain list
    def apply_filters(domains)
      filtered = domains

      # Filter by orphaned status
      if option.orphaned
        filtered = filtered.select { |d| d.org_id.to_s.empty? }
      end

      # Filter by organization
      if option.org_id
        filtered = filtered.select { |d| d.org_id.to_s == option.org_id.to_s }
      end

      # Filter by verification status
      if option.verified
        filtered = filtered.select { |d| d.verified.to_s == 'true' }
      elsif option.unverified
        filtered = filtered.select { |d| d.verified.to_s != 'true' }
      end

      filtered
    end

    # Helper: Format domain row for list display
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

    # Helper: Get organization info for display
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

    # Helper: Load domain by display name
    def load_domain_by_name(domain_name)
      domain = Onetime::CustomDomain.load_by_display_domain(domain_name)
      unless domain
        puts "Error: Domain '#{domain_name}' not found"
        return nil
      end
      domain
    end

    # Helper: Load organization by ID
    def load_organization(org_id, silent: false)
      org = Onetime::Organization.load(org_id)
      unless org
        puts "Error: Organization '#{org_id}' not found" unless silent
        return nil
      end
      org
    end

    # Helper: Format timestamp for display
    def format_timestamp(timestamp)
      return 'N/A' unless timestamp
      Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S UTC')
    rescue StandardError
      'invalid'
    end

    # Helper: Confirm action with user
    def confirm_action(message)
      return true if option.force
      print "#{message} [y/N]: "
      response = $stdin.gets.chomp
      response.downcase == 'y'
    end

    # Legacy methods for revalidate_domains command
    def get_domains_to_process
      if option.domain && option.custid
        get_specific_domain
      elsif option.custid
        get_customer_domains
      elsif option.domain
        get_domains_by_name
      else
        Onetime::CustomDomain.all
      end
    end

    def get_specific_domain
        domain = Onetime::CustomDomain.load(option.domain, option.custid)
        [domain]
    rescue Onetime::RecordNotFound
        puts "Domain #{option.domain} not found for customer #{option.custid}"
        nil
    end

    def get_customer_domains
      customer = Onetime::Customer.load(option.custid)
      unless customer
        puts "Customer #{option.custid} not found"
        return nil
      end

      begin
        customer.custom_domains.members.map do |domain_name|
          Onetime::CustomDomain.load(domain_name, option.custid)
        end
      rescue Onetime::RecordNotFound
        puts "Customer #{option.custid} not found"
        nil
      end
    end

    def get_domains_by_name
      matching_domains = Onetime::CustomDomain.all.select do |domain|
        domain.display_domain == option.domain
      end

      if matching_domains.empty?
        puts "Domain #{option.domain} not found"
        nil
      else
        matching_domains
      end
    end

    def process_domains_in_batches(domains)
      batch_size       = 10
      throttle_seconds = 4

      domains.each_slice(batch_size).with_index do |batch, batch_idx|
        puts "\nProcessing batch #{batch_idx + 1}..."
        process_batch(batch)

        # Throttle between batches
        if batch_idx < (domains.size.to_f / batch_size).ceil - 1
          puts "\nWaiting #{throttle_seconds} seconds before next batch..."
          sleep throttle_seconds
        end
      end
    end

    def process_batch(batch)
      batch.each do |domain|
        print "Revalidating #{domain.display_domain}... "
        revalidate_domain(domain)
      end
      sleep 0.25 # maintain a sane maximum of 4 requests per second
    end

    def revalidate_domain(domain)
        params           = { domain: domain.display_domain }
        # NOTE: This uses an old initialization signature that may be broken
        # TODO: CLI commands need proper strategy_result construction or different pattern
        verifier         = AccountAPI::Logic::Domains::VerifyDomain.new(nil, domain.custid, params)
        verifier.raise_concerns
        verifier.process
        status           = domain.verification_state
        resolving_status = domain.resolving == 'true' ? 'resolving' : 'not resolving'
        puts "#{status} (#{resolving_status})"
    rescue StandardError => ex
        puts "error: #{ex.message}"
        warn ex.backtrace
    end
  end
end
