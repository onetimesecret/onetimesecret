# lib/onetime/cli/change_email.rb

module Onetime
  class ChangeEmailCommand < Drydock::Command
    # CLI command to view email change reports
    def change_email_log
      # Default limit is 10 reports, can be overridden with --limit or -n option
      limit        = option.limit || 10
      email_filter = argv.first

      puts "Viewing recent email change reports#{" for #{email_filter}" if email_filter} (limit: #{limit})"
      puts '=' * 50

      # Connect to the database DB 0 where audit logs are stored
      redis = Familia.dbclient

      # Get keys matching the pattern
      pattern = email_filter ? "change_email:#{email_filter}:*" : 'change_email:*'
      keys    = redis.keys(pattern).sort_by { |k| k.split(':').last.to_i }.reverse.first(limit.to_i)

      if keys.empty?
        puts "No email change reports found#{" for #{email_filter}" if email_filter}."
        return
      end

      keys.each_with_index do |key, idx|
        parts     = key.split(':')
        old_email = parts[1]
        new_email = parts[2]
        timestamp = Time.at(parts[3].to_i)

        puts "#{idx+1}. #{old_email} → #{new_email} (#{timestamp.strftime('%Y-%m-%d %H:%M:%S')})"

        next unless option.verbose

        # Show full report in verbose mode
        report = redis.get(key)
        if report
          puts '-' * 40
          puts report
          puts '-' * 40
        else
          puts '  Report data not available'
        end
      end

      # Provide instructions for viewing specific reports
      unless option.verbose
        puts "\nTo view a specific report in full:"
        puts '  ots change-email-log --verbose OLDEMAIL'
      end
    end

    # CLI command implementation for changing customer email addresses.
    #
    # This command provides an interactive interface for the email address change process,
    # handling validation, confirmation, execution and reporting. It interfaces with the
    # ChangeEmail service which performs the actual data updates.
    #
    # The command supports changing a customer's email address with or without associated
    # custom domains. When domains are involved, it automatically calculates the required
    # ID changes.
    #
    # @see Onetime::Services::ChangeEmail
    # Command to change customer email addresses
    def change_email # rubocop:disable Metrics/MethodLength
      if argv.length < 2
        puts 'Usage: ots change-email OLD_EMAIL NEW_EMAIL [REALM]'
        puts "  Change a customer's email address and update related records."
        puts ''
        puts '  Arguments:'
        puts '    OLD_EMAIL    Current email address of the customer'
        puts '    NEW_EMAIL    New email address to change to'
        puts '    REALM        Optional: Geographic region (US/EU/CA/NZ), defaults to US'
        puts ''
        puts '  Example:'
        puts '    ots change-email user@example.com new@example.com'
        puts ''
        puts '  Note: Custom domains associated with this customer will be'
        puts '  automatically detected and updated.'
        return
      end

      old_email = argv[0]
      new_email = argv[1]
      realm     = argv[2] || 'US'
      domains   = []

      # Load customer to check if exists
      customer = begin
                   V2::Customer.load(old_email)
      rescue StandardError
                   nil
      end
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
            old_id         = domain.identifier
            puts "  #{index+1}. #{display_domain} (ID: #{old_id})"
            domains << { domain: display_domain, old_id: old_id }
          end
        else
          puts 'No custom domains associated with this customer.'
        end
      rescue StandardError => ex
        puts "Warning: Error detecting custom domains: #{ex.message}"
        puts ex.backtrace.join("\n") if OT.debug?
      end

      # Initialize the email change service
      # This service handles all validation and execution logic for email changes
      require_relative '../services/change_email'
      service = Onetime::Services::ChangeEmail.new(old_email, new_email, realm, domains)

      # Validate all inputs and domain relationships before executing changes
      # This ensures we catch any issues before modifying data
      # First validate
      begin
        if service.validate!
          puts 'Validation passed. Ready to execute changes.'

          # Display summary of changes
          puts "\nPREVIEW OF CHANGES:"
          puts service.summarize_changes
          puts

          print 'Proceed with email change? (y/n): '
          confirm = STDIN.gets.chomp.downcase

          if confirm == 'y'
            if service.execute!
              puts "\nEmail change completed successfully."

              # Verify the change was successful by checking relevant records
              puts "\nVerifying changes..."
              verify_success = false # Default to false, only set to true if all checks pass

              puts
              puts "  customer can now use: #{new_email}"
              puts

              # Check customer record exists with new email
              if V2::Customer.exists?(new_email)
                # If this is the only check, or all other checks also pass,
                # then we can set verify_success to true.
                # For now, let's assume we need to check domains too.
                # If there are no domains, this branch means success.
                verify_success = true unless domains.any?
              else
                puts "ERROR: Customer record with new email #{new_email} not found!"
                # verify_success remains false
              end

              # Check domains were migrated properly
              if domains.any?
                all_domains_verified = true # Assume true initially for domain checks
                puts 'Checking domain mappings:'
                domains.each_with_index do |domain_info, index|
                  domain            = domain_info[:domain]
                  stored_domain_id  = domain_info[:old_id]
                  # Check display_domains mapping still exists
                  current_domain_id = V2::CustomDomain.dbclient.hget('customdomain:display_domains', domain)

                  if current_domain_id == stored_domain_id
                    puts "  ✓ Domain #{index+1}: #{domain} still correctly mapped to #{current_domain_id}"
                  else
                    puts "  ✗ Domain #{index+1}: #{domain} mapping issue - stored: #{stored_domain_id}, current: #{current_domain_id}"
                    all_domains_verified = false
                  end
                end
                # Final success depends on both customer and all domains being verified
                verify_success       = V2::Customer.exists?(new_email) && all_domains_verified
              end

              if verify_success
                puts "\n✅ Verification successful! All records updated properly."
              else
                puts "\n❌ Verification failed! Some records may not be properly updated."
                puts '   This may indicate an issue with the update process.'
              end

              # Save report to the database for permanent audit trail
              report_key = service.save_report_to_db

              puts "Email change completed and logged to the database with key: #{report_key}"
            else
              puts "\nEmail change failed. See log for details."
              exit 1
            end
          else
            puts 'Operation cancelled.'
          end
        end
      rescue StandardError => ex
        # Handle validation and execution errors with descriptive messages
        puts "Error during operation: #{ex.message}"
        puts 'Check the domain mappings carefully. If there are issues with domain associations,'
        puts 'this may indicate data corruption or manual changes to database keys.'

        puts ex.backtrace.join("\n") if OT.debug?
        exit 1
      end
    end

    # Helper method to fetch a specific email change report from the database
    # @param key [String] The database key for the report
    # @return [String, nil] The report text or nil if not found
    def get_change_email_report(key)
      redis = Familia.dbclient
      redis.get(key)
    end
  end
end
