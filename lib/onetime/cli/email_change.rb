# lib/onetime/cli/email_change.rb

module Onetime
  class CLI < Drydock::Command
    # CLI command to view email change reports
    def view_email_changes
      # Default limit is 10 reports, can be overridden with --limit or -n option
      limit = option.limit || 10
      email_filter = argv.first

      puts "Viewing recent email change reports#{email_filter ? " for #{email_filter}" : ""} (limit: #{limit})"
      puts "=" * 50

      # Connect to Redis DB 0 where audit logs are stored
      redis = Familia.redis

      # Get keys matching the pattern
      pattern = email_filter ? "email_change:#{email_filter}:*" : "email_change:*"
      keys = redis.keys(pattern).sort_by { |k| k.split(':').last.to_i }.reverse.first(limit.to_i)

      if keys.empty?
        puts "No email change reports found#{email_filter ? " for #{email_filter}" : ""}."
        return
      end

      keys.each_with_index do |key, idx|
        parts = key.split(':')
        old_email = parts[1]
        new_email = parts[2]
        timestamp = Time.at(parts[3].to_i)

        puts "#{idx+1}. #{old_email} → #{new_email} (#{timestamp.strftime('%Y-%m-%d %H:%M:%S')})"

        if option.verbose
          # Show full report in verbose mode
          report = redis.get(key)
          if report
            puts "-" * 40
            puts report
            puts "-" * 40
          else
            puts "  Report data not available"
          end
        end
      end

      # Provide instructions for viewing specific reports
      unless option.verbose
        puts "\nTo view a specific report in full:"
        puts "  ots view-email-changes --verbose OLDEMAIL"
      end
    end

    # CLI command implementation for changing customer email addresses.
    #
    # This command provides an interactive interface for the email address change process,
    # handling validation, confirmation, execution and reporting. It interfaces with the
    # EmailChange service which performs the actual data updates.
    #
    # The command supports changing a customer's email address with or without associated
    # custom domains. When domains are involved, it automatically calculates the required
    # ID changes.
    #
    # @see Onetime::Services::EmailChange
    # Command to change customer email addresses
    def change_email # rubocop:disable Metrics/MethodLength
      if argv.length < 2
        puts "Usage: ots change-email OLD_EMAIL NEW_EMAIL [REALM]"
        puts "  Change a customer's email address and update related records."
        puts ""
        puts "  Arguments:"
        puts "    OLD_EMAIL    Current email address of the customer"
        puts "    NEW_EMAIL    New email address to change to"
        puts "    REALM        Optional: Geographic region (US/EU/CA/NZ), defaults to US"
        puts ""
        puts "  Example:"
        puts "    ots change-email user@example.com new@example.com"
        puts ""
        puts "  Note: Custom domains associated with this customer will be"
        puts "  automatically detected and updated."
        return
      end

      old_email = argv[0]
      new_email = argv[1]
      realm = argv[2] || "US"
      domains = []

      # Load customer to check if exists
      customer = V2::Customer.load(old_email) rescue nil
      if customer.nil?
        puts "Error: Customer with email #{old_email} not found"
        exit 1
      end

      # Auto-detect custom domains associated with this customer
      puts "Scanning for custom domains associated with #{old_email}..."
      begin
        custom_domains = customer.custom_domains_list
        if custom_domains.any?
          puts "Found #{custom_domains.size} domain(s) associated with customer:"
          custom_domains.each_with_index do |domain, index|
            display_domain = domain.display_domain
            old_id = domain.identifier
            puts "  #{index+1}. #{display_domain} (ID: #{old_id})"
            domains << {domain: display_domain, old_id: old_id}
          end
        else
          puts "No custom domains associated with this customer."
        end
      rescue => e
        puts "Warning: Error detecting custom domains: #{e.message}"
        puts e.backtrace.join("\n") if OT.debug?
      end

      # Initialize the email change service
      # This service handles all validation and execution logic for email changes
      require_relative '../services/email_change'
      service = Onetime::Services::EmailChange.new(old_email, new_email, realm, domains)

      # Validate all inputs and domain relationships before executing changes
      # This ensures we catch any issues before modifying data
      # First validate
      begin
        if service.validate!
          puts "Validation passed. Ready to execute changes."

          # Display summary of changes
          puts "\nPREVIEW OF CHANGES:"
          puts service.summarize_changes
          puts

          print "Proceed with email change? (y/n): "
          confirm = STDIN.gets.chomp.downcase

          if confirm == 'y'
            if service.execute!
              puts "\nEmail change completed successfully."

              # Verify the change was successful by checking relevant records
              puts "\nVerifying changes..."
              verify_success = true

              # Check customer record exists with new email
              unless V2::Customer.exists?(new_email)
                puts "ERROR: Customer record with new email #{new_email} not found!"
                verify_success = false
              end

              # Check domains were migrated properly
              if domains.any?
                puts "Checking domain mappings:"
                domains.each_with_index do |domain_info, index|
                  domain = domain_info[:domain]
                  # Check display_domains mapping
                  new_domain_id = V2::CustomDomain.redis.hget("customdomain:display_domains", domain)
                  calculated_id = [domain, new_email].gibbler.shorten

                  if new_domain_id == calculated_id
                    puts "  ✓ Domain #{index+1}: #{domain} correctly mapped to #{new_domain_id}"
                  else
                    puts "  ✗ Domain #{index+1}: #{domain} incorrectly mapped to #{new_domain_id} (expected: #{calculated_id})"
                    verify_success = false
                  end
                end
              end

              if verify_success
                puts "\n✅ Verification successful! All records updated properly."
              else
                puts "\n❌ Verification failed! Some records may not be properly updated."
                puts "   This may indicate an issue with the update process."
              end

              # Save report to Redis for permanent audit trail
              report_key = service.save_report_to_redis

              # Also save report to file for convenience
              report_file = "email_change_#{old_email}_to_#{new_email}_#{Time.now.strftime('%Y%m%d%H%M%S')}.log"
              log_dir = File.join(Onetime::HOME, 'log')

              if File.exist?(log_dir)
                log_path = File.join(log_dir, report_file)
                File.write(log_path, service.generate_report)
                puts "Report also saved to file: #{log_path}"
              end

              puts "Email change completed and logged to Redis with key: #{report_key}"
            else
              puts "\nEmail change failed. See log for details."
              exit 1
            end
          else
            puts "Operation cancelled."
          end
        end
      rescue => e
        # Handle validation and execution errors with descriptive messages
        puts "Error during operation: #{e.message}"
        puts "Check the domain IDs carefully. If there's a mismatch between stored and calculated IDs,"
        puts "this may indicate data corruption or manual changes to Redis keys."

        puts e.backtrace.join("\n") if OT.debug?
        exit 1
      end
    end

    # Helper method to fetch a specific email change report from Redis
    # @param key [String] The Redis key for the report
    # @return [String, nil] The report text or nil if not found
    def get_email_change_report(key)
      redis = Familia.redis
      redis.get(key)
    end
  end
end
