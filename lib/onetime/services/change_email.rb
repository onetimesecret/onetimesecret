# lib/onetime/services/change_email.rb

module Onetime
  module Services
    # Service class for managing customer email address changes.
    #
    # This service handles the complex process of changing a customer's email address,
    # which involves updating multiple database keys and maintaining relationships
    # between customers and their custom domains.
    #
    # When changing an email address, all of the following need to be updated:
    # 1. Customer record fields (custid, key, email)
    # 2. database keys associated with the customer (object, custom_domain, metadata)
    # 3. References in sorted sets and hashes (onetime:customer)
    # Note: Custom domain IDs are now randomly generated and don't need updating
    #
    # @example Basic usage
    #   service = Onetime::Services::ChangeEmail.new('old@example.com', 'new@example.com', 'US')
    #   service.validate!
    #   service.execute!
    #
    # @example With custom domains
    #   domains = [{domain: 'example.com', old_id: 'abc123def'}]
    #   service = Onetime::Services::ChangeEmail.new('old@example.com', 'new@example.com', 'US', domains)
    #   service.validate!
    #   service.execute!
    class ChangeEmail
      attr_reader :old_email, :new_email, :realm, :domains, :log_entries

      # Initializes the email change service with the necessary information.
      #
      # @param old_email [String] The current email address of the customer
      # @param new_email [String] The new email address to change to
      # @param realm [String] Geographic region (US/EU/CA/NZ) for auditing purposes
      # @param domains [Array<Hash>] Array of domain hashes with :domain and :old_id keys (for reporting only)
      #   Each hash should contain:
      #   - :domain [String] The domain name (e.g., 'example.com')
      #   - :old_id [String] The current domain ID (no longer needs updating)
      def initialize(old_email, new_email, realm, domains = [])
        @old_email       = old_email
        @new_email       = new_email
        @realm           = realm
        @domains         = domains || []
        @log_entries     = []
        @domain_mappings = {}

        # Redis instances are defined in the execution methods
      end

      # Generates a summary of changes that will be made during execution
      # @return [String] A human-readable summary of changes
      def summarize_changes
        changes = ['CHANGES TO BE MADE:',
                   '===================',
                   "1. Change customer email from #{old_email} to #{new_email}",
                   '2. Update the following database keys:',
                   "   - customer:#{old_email}:object → customer:#{new_email}:object",
                   "   - customer:#{old_email}:custom_domain → customer:#{new_email}:custom_domain (if exists)",
                   "   - customer:#{old_email}:metadata → customer:#{new_email}:metadata (if exists)",
                   "   - customer:#{old_email}:feature_flags → customer:#{new_email}:feature_flags (if exists)",
                   "   - customer:#{old_email}:reset_secret → customer:#{new_email}:reset_secret (if exists)",
                   '3. Update customer in values sorted set (onetime:customer)']

        # Note domain associations if any (no changes needed since domain IDs are now random)
        if @domains.any?
          changes << '4. Associated custom domain(s) (no changes required):'
          @domains.each do |domain_info|
            domain = domain_info[:domain]
            old_id = domain_info[:old_id]
            changes << "   - Domain: #{domain} (ID: #{old_id})"
          end
          changes << "   Note: Domain IDs are randomly generated and don't need updating"
        end

        changes.join("\n")
      end

      # Validates all inputs and domain relationships before making changes.
      #
      # Performs the following validations:
      # 1. Verifies the old email exists in the system
      # 2. Verifies the new email doesn't already exist
      # 3. For each domain, validates:
      #    - The domain format is valid
      #    - The provided old domain ID matches calculated ID
      #    - The domain exists in customdomain:display_domains
      #
      # @return [Boolean] True if all validations pass
      # @raise [RuntimeError] If any validation fails, with a descriptive error message
      def validate!
        log 'VALIDATION: Starting validation checks'

        # Check old email exists
        unless Onetime::Customer.exists?(old_email)
          raise "ERROR: Old email #{old_email} does not exist"
        end

        # Check new email doesn't already exist
        if Onetime::Customer.exists?(new_email)
          raise "ERROR: New email #{new_email} already exists"
        end

        # If we have domains to update, validate them
        if domains.any?
          validate_domains
        else
          log 'No domains to validate'
        end

        log 'VALIDATION: All checks passed'
        true
      end

      # Validates domain information for reporting purposes.
      #
      # For each domain in the domains array:
      # 1. Verifies domain format
      # 2. Verifies domain exists in display_domains
      # Note: Domain IDs no longer need validation since they're randomly generated
      #
      # @private
      def validate_domains
        domains.each do |domain_info|
          domain = domain_info[:domain]
          old_id = domain_info[:old_id]

          # Verify domain format
          unless domain && !domain.empty?
            raise "ERROR: Invalid domain format for domain entry: #{domain_info.inspect}"
          end

          # Check domain exists in display_domains
          display_domains_id = Onetime::CustomDomain.dbclient.hget('customdomain:display_domains', domain)
          if display_domains_id.to_s.empty?
            raise "ERROR: Domain '#{domain}' not found in display_domains mapping"
          end

          log "Domain verified: #{domain} (ID: #{old_id})"
        end
      end

      # Executes the email change process by updating customer-related database keys.
      #
      # This process:
      # 1. Updates customer object fields (custid, key, email)
      # 2. Renames all database keys associated with the customer
      # 3. Updates the customer in the customer values sorted set
      # Note: Custom domain records no longer need updating
      #
      # All operations are logged for audit purposes.
      #
      # @return [Boolean] True if all operations succeeded, false if any errors occurred
      def execute!
        # Get the redis connection via the model to make sure we're
        # connected to the correct DB where customer records live.
        redis = Onetime::Customer.dbclient

        log "EXECUTION: Starting email change process for #{old_email} -> #{new_email}"
        log "Using Redis database #{redis.connection[:db]}"

        begin
          redis.multi do |multi|
            # Update customer object fields
            log 'Updating customer object fields'
            multi.hset("customer:#{old_email}:object", 'custid', new_email)
            multi.hset("customer:#{old_email}:object", 'key', new_email)
            multi.hset("customer:#{old_email}:object", 'email', new_email)

            # Rename customer keys
            log 'Renaming customer keys'
            multi.rename("customer:#{old_email}:object", "customer:#{new_email}:object")

            # These keys might not exist for all customers, so check first
            # Note: Redis EXISTS command cannot be used inside a MULTI block.
            # We'll attempt the RENAME and it will fail if the key doesn't exist,
            # which is acceptable for this use case. If a more graceful handling
            # is needed, these checks would need to be done before the MULTI block.
            multi.rename("customer:#{old_email}:custom_domain", "customer:#{new_email}:custom_domain") if redis.exists?("customer:#{old_email}:custom_domain")
            multi.rename("customer:#{old_email}:metadata", "customer:#{new_email}:metadata") if redis.exists?("customer:#{old_email}:metadata")
            multi.rename("customer:#{old_email}:feature_flags", "customer:#{new_email}:feature_flags") if redis.exists?("customer:#{old_email}:feature_flags")
            multi.rename("customer:#{old_email}:reset_secret", "customer:#{new_email}:reset_secret") if redis.exists?("customer:#{old_email}:reset_secret")

            # Update customer values list
            # Get score for the old email in the sorted set
            # Note: ZSCORE cannot be used inside a MULTI block.
            # This operation needs to be handled carefully.
            # For now, we'll assume this is done outside or before the transaction.
            # A possible approach is to fetch the score before the multi block.
            score = redis.zscore('onetime:customer', old_email)
            if score
              multi.zadd('onetime:customer', score, new_email)
              multi.zrem('onetime:customer', old_email)
            end
          end

          log 'EXECUTION: Email change completed successfully'
          true
        rescue Redis::CommandError => ex
          # Specific handling for errors during EXEC
          log "ERROR during Redis transaction: #{ex.message}"
          log ex.backtrace.join("\n")
          # Attempt to unwatch if a watch was used, though not explicitly here
          redis.unwatch if redis.respond_to?(:unwatch)
          false
        rescue StandardError => ex
          log "ERROR: #{ex.message}"
          log ex.backtrace.join("\n")
          false
        end
      end

      # Logs a message to the internal log and stdout with timestamp.
      #
      # Each log message is:
      # 1. Added to the internal log entries array for the final report
      # 2. Logged to the OT info log with [cli.change-email] prefix
      # 3. Printed to stdout for real-time feedback (optionally)
      #
      # @param message [String] The message to log
      # @param stdout [Boolean] Whether to print the message to stdout
      def log(message, stdout = true)
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        entry     = "[#{timestamp}] #{message}"
        @log_entries << entry
        OT.info "[cli.change-email] #{message}" if stdout
      end

      # Generates a formatted report of all actions taken during the email change.
      #
      # The report includes:
      # 1. A header with old and new emails, realm, and affected domains
      # 2. A chronological log of all operations performed
      # 3. Timestamp and status information for each action
      #
      # This report is saved to the database DB 0 for audit purposes.
      #
      # @return [String] The formatted report as a single string
      def generate_report
        report = ['EMAIL CHANGE REPORT',
                  '=====================',
                  "Old Email: #{old_email}",
                  "New Email: #{new_email}",
                  "Realm: #{realm}",
                  "Domains: #{domains.map { |d| d[:domain] }.join(', ')}",
                  "Timestamp: #{Time.now}",
                  '=====================',
                  'LOG ENTRIES:']
        report.concat(log_entries)
        report.join("\n")
      end

      # Saves the report to the database DB 0 for auditing purposes
      # @return [String] The key where the report was stored
      def save_report_to_db
        report_text = generate_report
        timestamp   = Time.now.to_i
        report_key  = "change_email:#{old_email}:#{new_email}:#{timestamp}"

        # Save to the database DB 0 for audit logs
        redis = Familia.dbclient
        redis.set(report_key, report_text)
        redis.expire(report_key, 365 * 24 * 60 * 60) # 1 year TTL

        log "Report saved to the database with key: #{report_key}", true
        report_key
      end

      # @deprecated Use save_report_to_db instead
      # @return [String] The key where the report was stored
      alias_method :save_report_serialize_value, :save_report_to_db

      # Displays a preview of the changes to be made
      # @return [void]
      def display_preview
        puts summarize_changes
      end
    end
  end
end
