#!/usr/bin/env ruby
# lib/onetime/migrations/link_customers_to_rodauth.rb
#
# Migration script to link existing V2::Customer records to Rodauth accounts.
# This enables the transition from basic (Redis-only) to Rodauth (RDBMS+Redis) authentication.

require 'bundler/setup'
require 'sequel'
require 'bcrypt'
require_relative '../auth_config'
require_relative '../../../apps/api/v2/models/customer'

module Onetime
  module Migrations
    class LinkCustomersToRodauth
      attr_reader :config, :db, :stats

      def initialize(dry_run: true)
        @dry_run = dry_run
        @config = Onetime.auth_config
        @stats = {
          processed: 0,
          linked: 0,
          created: 0,
          skipped: 0,
          errors: 0
        }

        setup_database
        setup_logging
      end

      def migrate!
        puts "=" * 60
        puts "OneTimeSecret: Customer → Rodauth Account Migration"
        puts "=" * 60
        puts "Mode: #{@dry_run ? 'DRY RUN' : 'LIVE MIGRATION'}"
        puts "Database: #{@config.database_url}"
        puts "Time: #{Time.now}"
        puts

        validate_preconditions!

        # Get all non-anonymous customers
        customers = V2::Customer.values.to_a.reject(&:anonymous?)

        puts "Found #{customers.size} customers to process..."
        puts

        customers.each_with_index do |customer, index|
          process_customer(customer, index + 1, customers.size)
        end

        print_summary
      end

      private

      def setup_database
        @db = Sequel.connect(@config.database_url)

        # Enable logging in development
        if ENV['RACK_ENV'] == 'development'
          @db.loggers << Logger.new($stdout)
        end
      end

      def setup_logging
        @logger = Logger.new($stdout)
        @logger.level = @dry_run ? Logger::INFO : Logger::WARN
      end

      def validate_preconditions!
        # Check that Rodauth database exists and has the accounts table
        unless @db.table_exists?(:accounts)
          raise "Rodauth accounts table not found. Run Rodauth migrations first."
        end

        # Check that external_id column exists
        schema = @db.schema(:accounts)
        unless schema.any? { |col| col[0] == :external_id }
          raise "accounts.external_id column not found. Run migration 002_add_external_id.rb first."
        end

        # Check that we're not already in Rodauth mode
        if @config.rodauth_enabled?
          puts "WARNING: Already in Rodauth mode. This migration should typically be run before switching modes."
          print "Continue anyway? (y/N): "
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts "Migration aborted."
            exit 0
          end
        end

        puts "✓ Pre-conditions validated"
        puts
      end

      def process_customer(customer, index, total)
        @stats[:processed] += 1

        print "[#{index}/#{total}] Processing #{customer.custid}... "

        begin
          # Skip if customer already has a linked account
          if account_exists_for_customer?(customer)
            puts "SKIP (already linked)"
            @stats[:skipped] += 1
            return
          end

          # Create Rodauth account for this customer
          account_data = {
            email: customer.custid,  # In OTS, custid IS the email
            status_id: 2,           # Verified status
            created_at: customer.created || Time.now,
            external_id: customer.extid
          }

          if @dry_run
            puts "WOULD CREATE account with external_id: #{customer.extid}"
            @stats[:linked] += 1
          else
            # Create the account
            account_id = @db[:accounts].insert(account_data)

            # Create password hash if customer has a passphrase
            if customer.passphrase && !customer.passphrase.empty?
              # Use existing passphrase hash (assuming it's bcrypt compatible)
              @db[:account_password_hashes].insert(
                id: account_id,
                password_hash: customer.passphrase
              )
            end

            puts "CREATED account #{account_id} with external_id: #{customer.extid}"
            @stats[:created] += 1
            @stats[:linked] += 1
          end

        rescue => e
          puts "ERROR: #{e.message}"
          @logger.error "Failed to process customer #{customer.custid}: #{e.message}"
          @logger.error e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'
          @stats[:errors] += 1
        end
      end

      def account_exists_for_customer?(customer)
        # Check if an account already exists with this customer's extid
        @db[:accounts].where(external_id: customer.extid).count > 0
      rescue
        false
      end

      def print_summary
        puts
        puts "=" * 60
        puts "Migration Summary"
        puts "=" * 60
        puts "Customers processed: #{@stats[:processed]}"
        puts "Accounts linked:     #{@stats[:linked]}"
        puts "Accounts created:    #{@stats[:created]}"
        puts "Customers skipped:   #{@stats[:skipped]}"
        puts "Errors encountered:  #{@stats[:errors]}"
        puts

        if @dry_run
          puts "This was a DRY RUN. No changes were made."
          puts "To perform the actual migration, run with --live flag."
        else
          puts "Migration completed!"
          puts
          puts "Next steps:"
          puts "1. Update authentication.yml to set mode: rodauth"
          puts "2. Restart the application"
          puts "3. Test authentication flows"
        end

        puts
      end
    end
  end
end

# CLI interface
if __FILE__ == $0
  require 'optparse'

  options = {
    dry_run: true
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("--live", "Perform actual migration (default: dry run)") do
      options[:dry_run] = false
    end

    opts.on("--dry-run", "Perform dry run only (default)") do
      options[:dry_run] = true
    end

    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!

  # Load the OT environment
  require_relative '../../../lib/onetime'
  OT.boot! :test, false  # Boot without starting server

  # Run the migration
  migration = Onetime::Migrations::LinkCustomersToRodauth.new(
    dry_run: options[:dry_run]
  )

  migration.migrate!
end
