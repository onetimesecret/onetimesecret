# lib/onetime/services/change_email.rb

module Onetime
  module Services
    # Service class for managing customer email address changes.
    #
    # This service handles the complex process of changing a customer's email address,
    # which involves updating multiple Redis keys and maintaining relationships
    # between customers and their custom domains.
    #
    # When changing an email address, all of the following need to be updated:
    # 1. Customer record fields (custid, key, email)
    # 2. Redis keys associated with the customer (object, custom_domain, metadata)
    # 3. Custom domain relationships and IDs which are derived from email addresses
    # 4. References in sorted sets and hashes (onetime:customer, customdomain:values, etc.)
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
      # @param domains [Array<Hash>] Array of domain hashes with :domain and :old_id keys
      #   Each hash should contain:
      #   - :domain [String] The domain name (e.g., 'example.com')
      #   - :old_id [String] The current domain ID derived from [domain, old_email]
      def initialize(old_email, new_email, realm, domains = [])
        @old_email = old_email
        @new_email = new_email
        @realm = realm
        @domains = domains || []
        @log_entries = []
        @domain_mappings = {}

        # Redis instances are defined in the execution methods
      end

      # Generates a summary of changes that will be made during execution
      # @return [String] A human-readable summary of changes
      def summarize_changes
        changes = ["CHANGES TO BE MADE:",
                   "===================",
                   "1. Change customer email from #{old_email} to #{new_email}",
                   "2. Update the following Redis keys:",
                   "   - customer:#{old_email}:object → customer:#{new_email}:object",
                   "   - customer:#{old_email}:custom_domain → customer:#{new_email}:custom_domain (if exists)",
                   "   - customer:#{old_email}:metadata → customer:#{new_email}:metadata (if exists)",
                   "3. Update customer in values sorted set (onetime:customer)"]

        # Add domain changes if any
        if @domains.any?
          changes << "4. Update #{@domains.size} custom domain(s):"

          @domains.each do |domain_info|
            domain = domain_info[:domain]
            old_id = domain_info[:old_id]
            new_id = [domain, new_email].gibbler.shorten

            changes << "   - Domain: #{domain}"
            changes << "     Old ID: #{old_id}"
            changes << "     New ID: #{new_id}"
            changes << "     Keys to update:"
            changes << "       - customdomain:#{old_id}:object → customdomain:#{new_id}:object"
            changes << "       - customdomain:#{old_id}:brand → customdomain:#{new_id}:brand (if exists)"
            changes << "     Update in customdomain:values sorted set"
            changes << "     Update in customdomain:display_domains hash"
            changes << "     Update in customdomain:owners hash (if exists)"
          end
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
        log "VALIDATION: Starting validation checks"

        # Check old email exists
        unless V2::Customer.exists?(old_email)
          raise "ERROR: Old email #{old_email} does not exist"
        end

        # Check new email doesn't already exist
        if V2::Customer.exists?(new_email)
          raise "ERROR: New email #{new_email} already exists"
        end

        # If we have domains to update, validate them
        if domains.any?
          validate_domains
        else
          log "No domains to validate"
        end

        log "VALIDATION: All checks passed"
        true
      end

      # Validates all domain relationships and generates new domain IDs.
      #
      # For each domain in the domains array:
      # 1. Verifies domain format
      # 2. Checks if calculated old domain ID matches provided ID
      # 3. Verifies domain exists in display_domains with correct ID
      # 4. Calculates new domain ID based on new email
      # 5. Stores mapping from old ID to new ID for later update
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

          # Verify calculated old ID matches provided ID
          calculated_id = [domain, old_email].gibbler.shorten
          if calculated_id != old_id
            raise "ERROR: For domain '#{domain}': Calculated domain ID (#{calculated_id}) does not match provided ID (#{old_id})"
          end

          # Check domain exists in display_domains
          display_domains_id = V2::CustomDomain.redis.hget("customdomain:display_domains", domain)
          if !display_domains_id.to_s.empty? && display_domains_id != old_id
            raise "ERROR: For domain '#{domain}': domain ID in display_domains (#{display_domains_id}) does not match expected ID (#{old_id})"
          end

          # Calculate new domain ID
          new_id = [domain, new_email].gibbler.shorten
          @domain_mappings[old_id] = new_id
          log "Domain mapping: #{domain} => #{old_id} -> #{new_id}"
        end
      end

      # Executes the email change process by updating all related Redis keys.
      #
      # This process:
      # 1. Updates customer object fields (custid, key, email)
      # 2. Updates custom domain records if any exist
      # 3. Renames all Redis keys associated with the customer
      # 4. Updates the customer in the customer values sorted set
      #
      # All operations are logged for audit purposes.
      #
      # @return [Boolean] True if all operations succeeded, false if any errors occurred
      def execute!
        # Get the redis connection via the model to make sure we're
        # connected to the correct DB where customer records live.
        redis = V2::Customer.redis

        log "EXECUTION: Starting email change process for #{old_email} -> #{new_email}"
        log "Using Redis database #{redis.connection[:db]}"

        begin
          redis.multi do |multi|
            # Update customer object fields
            log "Updating customer object fields"
            multi.hset("customer:#{old_email}:object", "custid", new_email)
            multi.hset("customer:#{old_email}:object", "key", new_email)
            multi.hset("customer:#{old_email}:object", "email", new_email)

            # Update domain records if needed
            # This is called outside the multi block as it has its own multi block
            # update_domains

            # Rename customer keys
            log "Renaming customer keys"
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
            score = redis.zscore("onetime:customer", old_email)
            if score
              multi.zadd("onetime:customer", score, new_email)
              multi.zrem("onetime:customer", old_email)
            end
          end

          # Update domain records if needed (has its own multi block)
          update_domains if @domain_mappings.any?

          log "EXECUTION: Email change completed successfully"
          return true
        rescue Redis::CommandError => e
          # Specific handling for errors during EXEC
          log "ERROR during Redis transaction: #{e.message}"
          log e.backtrace.join("\n")
          # Attempt to unwatch if a watch was used, though not explicitly here
          redis.unwatch if redis.respond_to?(:unwatch)
          return false
        rescue => e
          log "ERROR: #{e.message}"
          log e.backtrace.join("\n")
          return false
        end
      end

      # Updates all domain records in Redis with the new email and IDs.
      #
      # For each domain mapping:
      # 1. Updates domain object fields (custid, key, domainid)
      # 2. Renames domain keys (brand, object)
      # 3. Updates domain in sorted sets and hashes
      # 4. Updates domain display mappings
      # 5. Updates domain ownership records
      #
      # Updates domain records in Redis
      # @private
      def update_domains
        redis = V2::CustomDomain.redis # Use CustomDomain's redis connection

        @domain_mappings.each do |old_domain_id, new_domain_id|
          log "Updating domain #{old_domain_id} -> #{new_domain_id}"

          begin
            redis.multi do |multi|
              # Update domain object fields
              multi.hset("customdomain:#{old_domain_id}:object", "custid", new_email)
              multi.hset("customdomain:#{old_domain_id}:object", "key", new_domain_id)
              multi.hset("customdomain:#{old_domain_id}:object", "domainid", new_domain_id)

              # Get domain score for later use
              # Note: ZSCORE cannot be used inside a MULTI block.
              # Fetch score before the multi block.
              domain_score = redis.zscore("customdomain:values", old_domain_id)
              log "Domain score: #{domain_score}" # Log score before multi

              # Check if brand key exists before renaming
              # Note: EXISTS cannot be used inside a MULTI block.
              # Perform this check before the multi block if critical,
              # otherwise, RENAME will fail gracefully if the key doesn't exist.
              multi.rename("customdomain:#{old_domain_id}:brand", "customdomain:#{new_domain_id}:brand") if redis.exists?("customdomain:#{old_domain_id}:brand")
              multi.rename("customdomain:#{old_domain_id}:logo", "customdomain:#{new_domain_id}:logo") if redis.exists?("customdomain:#{old_domain_id}:logo")
              multi.rename("customdomain:#{old_domain_id}:icon", "customdomain:#{new_domain_id}:icon") if redis.exists?("customdomain:#{old_domain_id}:icon")


              # Rename object key
              multi.rename("customdomain:#{old_domain_id}:object", "customdomain:#{new_domain_id}:object")

              # Update sorted sets and hashes
              if domain_score # Ensure score was fetched successfully
                multi.zadd("customdomain:values", domain_score, new_domain_id)
                multi.zrem("customdomain:values", old_domain_id)
              end

              # Update display domains
              domain = domains.find { |d| d[:old_id] == old_domain_id }[:domain]
              multi.hset("customdomain:display_domains", domain, new_domain_id)

              # Update the owners key if it exists
              # Note: HEXISTS cannot be used inside a MULTI block.
              # Perform this check before the multi block if critical.
              if redis.hexists("customdomain:owners", old_domain_id)
                multi.hdel("customdomain:owners", old_domain_id)
                multi.hset("customdomain:owners", new_domain_id, new_email)
              end

              # Update customer:domains mapping if it exists
              # Note: HEXISTS cannot be used inside a MULTI block.
              if redis.hexists("onetime:customers:domain", domain)
                multi.hset("onetime:customers:domain", domain, new_email)
              end
            end
          rescue Redis::CommandError => e
            log "ERROR during Redis transaction for domain #{old_domain_id}: #{e.message}"
            log e.backtrace.join("\n")
            # Attempt to unwatch if a watch was used
            redis.unwatch if redis.respond_to?(:unwatch)
            # Decide if we should re-raise or handle. For now, log and continue.
          rescue => e
            log "ERROR updating domain #{old_domain_id}: #{e.message}"
            log e.backtrace.join("\n")
            # Decide if we should re-raise or handle.
          end
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
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        entry = "[#{timestamp}] #{message}"
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
      # This report is saved to Redis DB 0 for audit purposes.
      #
      # @return [String] The formatted report as a single string
      def generate_report
        report = ["EMAIL CHANGE REPORT",
                  "=====================",
                  "Old Email: #{old_email}",
                  "New Email: #{new_email}",
                  "Realm: #{realm}",
                  "Domains: #{domains.map { |d| d[:domain] }.join(', ')}",
                  "Timestamp: #{Time.now}",
                  "=====================",
                  "LOG ENTRIES:"]
        report.concat(log_entries)
        report.join("\n")
      end

      # Saves the report to Redis DB 0 for auditing purposes
      # @return [String] The key where the report was stored
      def save_report_to_redis
        report_text = generate_report
        timestamp = Time.now.to_i
        report_key = "change_email:#{old_email}:#{new_email}:#{timestamp}"

        # Save to Redis DB 0 for audit logs
        redis = Familia.redis
        redis.set(report_key, report_text)
        redis.expire(report_key, 365 * 24 * 60 * 60) # 1 year TTL

        log "Report saved to Redis with key: #{report_key}", true
        report_key
      end

      # Displays a preview of the changes to be made
      # @return [void]
      def display_preview
        puts summarize_changes
      end
    end
  end
end
