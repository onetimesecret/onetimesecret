# lib/onetime/cli/email_change.rb

module Onetime
  class CLI < Drydock::Command
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
          custom_domains.each do |domain|
            display_domain = domain.display_domain
            old_id = domain.identifier
            puts "  - #{display_domain} (ID: #{old_id})"
            domains << {domain: display_domain, old_id: old_id}
          end
        else
          puts "No custom domains associated with this customer."
        end
      rescue => e
        puts "Warning: Error detecting custom domains: #{e.message}"
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
                domains.each do |domain_info|
                  domain = domain_info[:domain]
                  # Check display_domains mapping
                  new_domain_id = Familia.redis.hget("customdomain:display_domains", domain)
                  calculated_id = [domain, new_email].gibbler.shorten
                  unless new_domain_id == calculated_id
                    puts "ERROR: Domain #{domain} mapping is incorrect: #{new_domain_id} (expected: #{calculated_id})"
                    verify_success = false
                  end
                end
              end

              puts verify_success ? "Verification successful! All records updated properly." : "Verification failed! Some records may not be properly updated."

              # Save report to file
              report_file = "email_change_#{old_email}_to_#{new_email}_#{Time.now.strftime('%Y%m%d%H%M%S')}.log"

              # Write report to log directory if it exists
              log_dir = File.join(Onetime::HOME, 'log')
              log_path = File.exist?(log_dir) ? File.join(log_dir, report_file) : report_file

              File.write(log_path, service.generate_report)
              puts "Report saved to #{log_path}"
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
        puts "Error during validation: #{e.message}"
        exit 1
      end
    end
  end
end
