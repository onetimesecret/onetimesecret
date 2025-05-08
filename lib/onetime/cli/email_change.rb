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
    def change_email # rubocop:disable Metrics/MethodLength
      if argv.length < 2
        puts "Usage: ots change-email OLD_EMAIL NEW_EMAIL [REALM] [DOMAIN OLD_ID]..."
        puts "  Change a customer's email address and update related records."
        puts ""
        puts "  Arguments:"
        puts "    OLD_EMAIL    Current email address of the customer"
        puts "    NEW_EMAIL    New email address to change to"
        puts "    REALM        Optional: Geographic region (US/EU/CA/NZ), defaults to US"
        puts "    DOMAIN       Optional: Domain to update"
        puts "    OLD_ID       Optional: Current domain ID (must be specified with DOMAIN)"
        puts ""
        puts "  Example with custom domain:"
        puts "    ots change-email user@example.com new@example.com US example.com abc123def"
        puts ""
        puts "  Example without custom domain:"
        puts "    ots change-email user@example.com new@example.com"
        return
      end

      old_email = argv[0]
      new_email = argv[1]
      realm = argv[2] || "US"
      domains = []

      # Parse domain arguments (if any)
      if argv.length > 3
        (3...argv.length).step(2) do |i|
          if argv[i] && argv[i+1]
            domains << {domain: argv[i], old_id: argv[i+1]}
          end
        end
      end

      # Initialize the email change service
      # This service handles all validation and execution logic for email changes
      require_relative '../services/email_change'
      service = Onetime::Services::EmailChange.new(old_email, new_email, realm, domains)

      # Validate all inputs and domain relationships before executing changes
      # This ensures we catch any issues before modifying data
      begin
        if service.validate!
          puts "Validation passed. Ready to execute changes."
          print "Proceed with email change? (y/n): "
          confirm = STDIN.gets.chomp.downcase

          if confirm == 'y'
            if service.execute!
              puts "\nEmail change completed successfully."

              # Generate and save detailed audit report to a log file
              # This provides a permanent record of the change for compliance
              report_file = "email_change_#{old_email}_to_#{new_email}_#{Time.now.strftime('%Y%m%d%H%M%S')}.log"

              # Write report to the application log directory if it exists,
              # otherwise write to the current directory
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
