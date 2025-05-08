#!/usr/bin/env ruby
# email_change.rb

require_relative 'path/to/environment'

class EmailChangeService
  attr_reader :old_email, :new_email, :realm, :domains, :log_entries

  def initialize(old_email, new_email, realm, domains = [])
    @old_email = old_email
    @new_email = new_email
    @realm = realm
    @domains = domains || []
    @log_entries = []
    @domain_mappings = {}
    @redis = Redis.new(db: 6)
  end

  def validate!
    log "VALIDATION: Starting validation checks"

    # Check old email exists
    unless V2::Customer.exists?(old_email)
      raise "ERROR: Old email #{old_email} doesn't exist"
    end

    # Check new email doesn't already exist
    if V2::Customer.exists?(new_email)
      raise "ERROR: New email #{new_email} already exists"
    end

    # Validate domains
    domains.each do |domain_info|
      domain = domain_info[:domain]
      old_id = domain_info[:old_id]

      # Verify calculated old ID matches provided ID
      calculated_id = ['domain.example.com', old_email].gibbler.shorten
      if calculated_id != old_id
        raise "ERROR: Calculated domain ID (#{calculated_id}) doesn't match provided ID (#{old_id})"
      end

      # Check domain exists in display_domains
      stored_id = @redis.hget("customdomain:display_domains", domain)
      if stored_id != old_id
        raise "ERROR: Stored domain ID (#{stored_id}) doesn't match calculated ID (#{old_id})"
      end

      # Calculate new domain ID
      new_id = ['domain.example.com', new_email].gibbler.shorten
      @domain_mappings[old_id] = new_id
      log "Domain mapping: #{domain} => #{old_id} -> #{new_id}"
    end

    log "VALIDATION: All checks passed"
    true
  end

  def execute!
    log "EXECUTION: Starting email change process for #{old_email} -> #{new_email}"

    begin
      # Load old customer
      customer = V2::Customer.from_identifier(old_email)

      # Update customer object fields
      log "Updating customer object fields"
      @redis.hset("customer:#{old_email}:object", "custid", new_email)
      @redis.hset("customer:#{old_email}:object", "key", new_email)
      @redis.hset("customer:#{old_email}:object", "email", new_email)

      # Update domain records if needed
      @domain_mappings.each do |old_domain_id, new_domain_id|
        log "Updating domain #{old_domain_id} -> #{new_domain_id}"

        # Update domain object fields
        @redis.hset("customdomain:#{old_domain_id}:object", "custid", new_email)
        @redis.hset("customdomain:#{old_domain_id}:object", "key", new_domain_id)
        @redis.hset("customdomain:#{old_domain_id}:object", "domainid", new_domain_id)

        # Get domain score for later use
        domain_score = @redis.zscore("customdomain:values", old_domain_id)
        log "Domain score: #{domain_score}"

        # Rename keys
        @redis.rename("customdomain:#{old_domain_id}:brand", "customdomain:#{new_domain_id}:brand")
        @redis.rename("customdomain:#{old_domain_id}:object", "customdomain:#{new_domain_id}:object")

        # Update sorted sets and hashes
        @redis.zadd("customdomain:values", domain_score, new_domain_id)
        @redis.zrem("customdomain:values", old_domain_id)

        # Update display domains
        domain = domains.find { |d| d[:old_id] == old_domain_id }[:domain]
        @redis.hset("customdomain:display_domains", domain, new_domain_id)
      end

      # Rename customer keys
      log "Renaming customer keys"
      @redis.rename("customer:#{old_email}:object", "customer:#{new_email}:object")
      @redis.rename("customer:#{old_email}:custom_domain", "customer:#{new_email}:custom_domain")
      @redis.rename("customer:#{old_email}:metadata", "customer:#{new_email}:metadata")

      # Update customer values list
      # Note: This part depends on how customer:values is implemented
      # For now we'll assume it's a sorted set with emails as members

      log "EXECUTION: Email change completed successfully"
      return true
    rescue => e
      log "ERROR: #{e.message}"
      log e.backtrace.join("\n")
      return false
    end
  end

  def log(message)
    timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    entry = "[#{timestamp}] #{message}"
    @log_entries << entry
    puts entry
  end

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

# CLI interface
if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: #{$0} OLD_EMAIL NEW_EMAIL [REALM] [DOMAIN OLD_ID]..."
    exit 1
  end

  old_email = ARGV[0]
  new_email = ARGV[1]
  realm = ARGV[2] || "NA"
  domains = []

  # Parse domain arguments (if any)
  if ARGV.length > 3
    (3...ARGV.length).step(2) do |i|
      if ARGV[i] && ARGV[i+1]
        domains << {domain: ARGV[i], old_id: ARGV[i+1]}
      end
    end
  end

  service = EmailChangeService.new(old_email, new_email, realm, domains)

  # First validate
  begin
    if service.validate!
      puts "Validation passed. Ready to execute changes."
      print "Proceed with email change? (y/n): "
      confirm = STDIN.gets.chomp.downcase

      if confirm == 'y'
        if service.execute!
          puts "\nEmail change completed successfully."

          # Save report to file
          report_file = "email_change_#{old_email}_to_#{new_email}_#{Time.now.strftime('%Y%m%d%H%M%S')}.log"
          File.write(report_file, service.generate_report)
          puts "Report saved to #{report_file}"
        else
          puts "\nEmail change failed. See log for details."
        end
      else
        puts "Operation cancelled."
      end
    end
  rescue => e
    puts "Error during validation: #{e.message}"
    exit 1
  end
end
