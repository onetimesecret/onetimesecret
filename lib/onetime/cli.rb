# lib/onetime/cli.rb

require 'drydock'
require 'onetime'
require 'familia/tools'
require 'onetime/migration'

require 'v2/models'
require 'v2/logic'

# Load CLI commands
require_relative 'cli/email_change'

module Onetime
  class CLI < Drydock::Command
    def init
      # Make sure all the models are loaded before calling boot
      OT.boot! :cli
    end

    def migrate
      migration_file = argv.first

      unless migration_file
        puts "Usage: ots migrate MIGRATION_SCRIPT [--run]"
        puts "  --run    Actually apply changes (default is dry run mode)"
        puts "\nAvailable migrations:"
        Dir[File.join(Onetime::HOME, 'migrate', '*.rb')].each do |file|
          puts "  - #{File.basename(file)}"
        end
        return
      end

      migration_path = File.join(Onetime::HOME, 'migrate', migration_file)
      unless File.exist?(migration_path)
        puts "Migration script not found: #{migration_file}"
        return
      end

      begin
        # Load the migration script
        require_relative "../../migrate/#{migration_file}"

        # Run the migration with options
        success = Onetime::Migration.run(run: option.run)
        puts success ? "\nMigration completed successfully" : "\nMigration failed"
        exit(success ? 0 : 1)
      rescue LoadError => e
        puts "Error loading migration: #{e.message}"
        exit 1
      rescue StandardError => e
        puts "Migration error: #{e.message}"
        puts e.backtrace if OT.debug?
        exit 1
      end
    end

    def move_keys
      sourcedb, targetdb, filter = *argv
      raise 'No target database supplied' unless sourcedb && targetdb
      raise 'No filter supplied' unless filter

      source_uri = URI.parse Familia.uri.to_s
      target_uri = URI.parse Familia.uri.to_s
      source_uri.db = sourcedb
      target_uri.db = targetdb
      Familia::Tools.move_keys filter, source_uri, target_uri do |idx, type, key, ttl|
        if global.verbose > 0
          puts "#{idx + 1.to_s.rjust(4)} (#{type.to_s.rjust(6)}, #{ttl.to_s.rjust(4)}): #{key}"
        else
          print "\rMoved #{idx + 1} keys"
        end
      end
      puts
    end

    def customers
      puts '%d customers' % V2::Customer.values.size
      if option.list
        all_customers = V2::Customer.values.all.map do |custid|
          V2::Customer.load(custid)
        end

        # Choose the field to group by
        field = option.check_email ? :email : :custid

        # Group customers by the domain portion of the email address
        grouped_customers = all_customers.group_by do |cust|
          next if cust.nil?
          email = cust.send(field).to_s
          domain = email.split('@')[1] || 'unknown'
          domain
        end

        # Sort the grouped customers by domain
        grouped_customers.sort_by { |_, customers| customers.size }.each do |domain, customers|
          puts "#{domain} #{customers.size}"
        end

      elsif option.check
        all_customers = V2::Customer.values.all.map do |custid|
          V2::Customer.load(custid)
        end

        mismatched_customers = all_customers.select do |cust|
          next if cust.nil?
          custid_email = cust.custid.to_s
          email_field = cust.email.to_s
          custid_email != email_field
        end
        if mismatched_customers.empty?
          puts "All customers have matching custid and email fields."
        end

        mismatched_customers.each do |cust|
          obscured_custid = OT::Utils.obscure_email(cust.custid)
          obscured_email = OT::Utils.obscure_email(cust.email)
          puts "CustID and email mismatch: CustID: #{obscured_custid}, Email: #{obscured_email}"
        end
      end
    end

    def domains
      puts '%d custom domains' % V2::CustomDomain.values.size
      if option.list
        literally_all_domain_ids = V2::CustomDomain.values.all
        all_domains = literally_all_domain_ids.map do |did|
          V2::CustomDomain.from_identifier(did)
        end

        # Group domains by display_domain
        grouped_domains = all_domains.group_by(&:display_domain)

        grouped_domains.sort.each do |display_domain, domains|
          if domains.size == 1
            domain = domains.first
            puts '%s %s' % [display_domain, domain.rediskey]
          else
            rediskeys = domains.map(&:rediskey)
            rediskeys_display = if rediskeys.size > 3
                                  "#{rediskeys[0..2].join(', ')}, ..."
                                else
                                  rediskeys.join(', ')
                                end
            puts '%4d  %s (%s)' % [domains.size, display_domain, rediskeys_display]
          end
        end
      end
    end

    def revalidate_domains
      domains_to_process = get_domains_to_process
      return unless domains_to_process

      total = domains_to_process.size
      puts "Processing #{total} domain#{total == 1 ? '' : 's'}"

      process_domains_in_batches(domains_to_process)

      puts "\nRevalidation complete"
    end

    private

    def get_domains_to_process
      if option.domain && option.custid
        get_specific_domain
      elsif option.custid
        get_customer_domains
      elsif option.domain
        get_domains_by_name
      else
        V2::CustomDomain.all
      end
    end

    def get_specific_domain
      begin
        domain = V2::CustomDomain.load(option.domain, option.custid)
        [domain]
      rescue Onetime::RecordNotFound
        puts "Domain #{option.domain} not found for customer #{option.custid}"
        nil
      end
    end

    def get_customer_domains
      customer = V2::Customer.load(option.custid)
      unless customer
        puts "Customer #{option.custid} not found"
        return nil
      end

      begin
        customer.custom_domains.members.map do |domain_name|
          V2::CustomDomain.load(domain_name, option.custid)
        end
      rescue Onetime::RecordNotFound
        puts "Customer #{option.custid} not found"
        nil
      end
    end

    def get_domains_by_name
      matching_domains = V2::CustomDomain.all.select do |domain|
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
      batch_size = 10
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
      begin
        params = { domain: domain.display_domain }
        verifier = V2::Logic::Domains::VerifyDomain.new(nil, domain.custid, params)
        verifier.raise_concerns
        verifier.process
        status = domain.verification_state
        resolving_status = domain.resolving == 'true' ? 'resolving' : 'not resolving'
        puts "#{status} (#{resolving_status})"
      rescue => e
        puts "error: #{e.message}"
        $stderr.puts e.backtrace
      end
    end

    def require_sudo
      return if Process.uid.zero?
      raise 'Must run as root or with sudo'
    end
  end
end
