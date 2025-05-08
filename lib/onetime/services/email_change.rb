# lib/onetime/services/email_change.rb

module Onetime
  module Services
    # Service to handle customer email address changes
    # This handles updating Redis keys and relationships
    class EmailChange
      attr_reader :old_email, :new_email, :realm, :domains, :log_entries

      # @param old_email [String] The current email address
      # @param new_email [String] The new email address to change to
      # @param realm [String] Geographic region (US/EU/CA/NZ)
      # @param domains [Array<Hash>] Array of domain hashes with :domain and :old_id keys
      def initialize(old_email, new_email, realm, domains = [])
        @old_email = old_email
        @new_email = new_email
        @realm = realm
        @domains = domains || []
        @log_entries = []
        @domain_mappings = {}
        @redis = Familia.redis
      end

      # Validates all inputs and domain relationships before making changes
      # @return [Boolean] True if validation passes
      # @raise [RuntimeError] If validation fails
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

      # Validates all domain relationships
      # @private
      def validate_domains
        domains.each do |domain_info|
          domain = domain_info[:domain]
          old_id = domain_info[:old_id]

          # Verify domain format
          unless domain && !domain.empty?
            raise "ERROR: Invalid domain format"
          end

          # Verify calculated old ID matches provided ID
          calculated_id = [domain, old_email].gibbler.shorten
          if calculated_id != old_id
            raise "ERROR: Calculated domain ID (#{calculated_id}) does not match provided ID (#{old_id})"
          end

          # Check domain exists in display_domains
          stored_id = @redis.hget("customdomain:display_domains", domain)
          if stored_id != old_id
            raise "ERROR: Stored domain ID (#{stored_id}) does not match calculated ID (#{old_id})"
          end

          # Calculate new domain ID
          new_id = [domain, new_email].gibbler.shorten
          @domain_mappings[old_id] = new_id
          log "Domain mapping: #{domain} => #{old_id} -> #{new_id}"
        end
      end

      # Executes the email change process
      # @return [Boolean] True if all operations succeeded
      def execute!
        log "EXECUTION: Starting email change process for #{old_email} -> #{new_email}"

        begin
          # Update customer object fields
          log "Updating customer object fields"
          @redis.hset("customer:#{old_email}:object", "custid", new_email)
          @redis.hset("customer:#{old_email}:object", "key", new_email)
          @redis.hset("customer:#{old_email}:object", "email", new_email)

          # Update domain records if needed
          update_domains if @domain_mappings.any?

          # Rename customer keys
          log "Renaming customer keys"
          @redis.rename("customer:#{old_email}:object", "customer:#{new_email}:object")

          # These keys might not exist for all customers, so check first
          if @redis.exists?("customer:#{old_email}:custom_domain")
            @redis.rename("customer:#{old_email}:custom_domain", "customer:#{new_email}:custom_domain")
          end

          if @redis.exists?("customer:#{old_email}:metadata")
            @redis.rename("customer:#{old_email}:metadata", "customer:#{new_email}:metadata")
          end

          # Update customer values list
          # Get score for the old email in the sorted set
          score = @redis.zscore("onetime:customer", old_email)
          if score
            @redis.zadd("onetime:customer", score, new_email)
            @redis.zrem("onetime:customer", old_email)
          end

          log "EXECUTION: Email change completed successfully"
          return true
        rescue => e
          log "ERROR: #{e.message}"
          log e.backtrace.join("\n")
          return false
        end
      end

      # Updates domain records in Redis
      # @private
      def update_domains
        @domain_mappings.each do |old_domain_id, new_domain_id|
          log "Updating domain #{old_domain_id} -> #{new_domain_id}"

          # Update domain object fields
          @redis.hset("customdomain:#{old_domain_id}:object", "custid", new_email)
          @redis.hset("customdomain:#{old_domain_id}:object", "key", new_domain_id)
          @redis.hset("customdomain:#{old_domain_id}:object", "domainid", new_domain_id)

          # Get domain score for later use
          domain_score = @redis.zscore("customdomain:values", old_domain_id)
          log "Domain score: #{domain_score}"

          # Check if brand key exists before renaming
          if @redis.exists?("customdomain:#{old_domain_id}:brand")
            @redis.rename("customdomain:#{old_domain_id}:brand", "customdomain:#{new_domain_id}:brand")
          end

          # Rename object key
          @redis.rename("customdomain:#{old_domain_id}:object", "customdomain:#{new_domain_id}:object")

          # Update sorted sets and hashes
          @redis.zadd("customdomain:values", domain_score, new_domain_id)
          @redis.zrem("customdomain:values", old_domain_id)

          # Update display domains
          domain = domains.find { |d| d[:old_id] == old_domain_id }[:domain]
          @redis.hset("customdomain:display_domains", domain, new_domain_id)

          # Update the owners key if it exists
          if @redis.hexists("customdomain:owners", old_domain_id)
            @redis.hdel("customdomain:owners", old_domain_id)
            @redis.hset("customdomain:owners", new_domain_id, new_email)
          end
        end
      end

      # Logs a message to the internal log and stdout
      # @param message [String] The message to log
      def log(message)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        entry = "[#{timestamp}] #{message}"
        @log_entries << entry
        OT.info "[EMAIL_CHANGE] #{message}"
        puts entry
      end

      # Generates a report of all actions taken
      # @return [String] The formatted report
      def generate_report
        report = ["EMAIL CHANGE REPORT",
                  "=====================",
                  "Old Email: #{old_email}",
                  "New Email: #{new_email}",
                  "Realm: #{realm}",
                  "Domains: #{domains.inspect}",
                  "=====================",
                  "LOG ENTRIES:"]
        report.concat(log_entries)
        report.join("\n")
      end
    end
  end
end
