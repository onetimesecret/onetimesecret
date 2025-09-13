#!/usr/bin/env ruby
# lib/onetime/migrations/preserve_sessions_during_migration.rb
#
# Session preservation script for authentication mode migration.
# Ensures existing Redis sessions continue working when switching from basic to Rodauth mode.

require 'bundler/setup'
require 'familia'
require 'sequel'
require_relative '../auth_config'

module Onetime
  module Migrations
    class PreserveSessionsDuringMigration
      attr_reader :config, :db, :redis, :stats

      def initialize(dry_run: true)
        @dry_run = dry_run
        @config = Onetime.auth_config
        @stats = {
          sessions_found: 0,
          sessions_migrated: 0,
          sessions_invalid: 0,
          customers_not_found: 0,
          accounts_not_found: 0,
          errors: 0
        }

        setup_connections
        setup_logging
      end

      def migrate!
        puts "=" * 60
        puts "OneTimeSecret: Session Preservation During Migration"
        puts "=" * 60
        puts "Mode: #{@dry_run ? 'DRY RUN' : 'LIVE MIGRATION'}"
        puts "Time: #{Time.now}"
        puts

        validate_preconditions!
        scan_and_update_sessions
        print_summary
      end

      private

      def setup_connections
        # Setup Redis connection (Familia)
        Familia.uri = @config.session['redis_url'] || 'redis://localhost:6379/0'
        @redis = Familia.dbclient

        # Setup database connection
        @db = Sequel.connect(@config.database_url)
      end

      def setup_logging
        @logger = Logger.new($stdout)
        @logger.level = @dry_run ? Logger::INFO : Logger::WARN
      end

      def validate_preconditions!
        # Check Redis connection
        @redis.ping
        puts "✓ Redis connection established"

        # Check database connection
        @db.test_connection
        puts "✓ Database connection established"

        # Check that accounts table has external_id
        unless @db.table_exists?(:accounts)
          raise "Rodauth accounts table not found"
        end

        schema = @db.schema(:accounts)
        unless schema.any? { |col| col[0] == :external_id }
          raise "accounts.external_id column not found"
        end

        puts "✓ Pre-conditions validated"
        puts
      end

      def scan_and_update_sessions
        puts "Scanning Redis for active sessions..."

        # Find all session keys
        session_pattern = "#{@config.session['redis_prefix'] || 'session'}:*"
        session_keys = @redis.keys(session_pattern)

        @stats[:sessions_found] = session_keys.size
        puts "Found #{session_keys.size} sessions to examine"
        puts

        session_keys.each_with_index do |session_key, index|
          process_session(session_key, index + 1, session_keys.size)
        end
      end

      def process_session(session_key, index, total)
        print "[#{index}/#{total}] Processing #{session_key}... "

        begin
          # Get session data
          session_data = @redis.get(session_key)
          return handle_invalid_session("no data") unless session_data

          # Parse session data (assuming Marshal format like RedisFamilia)
          session = begin
            Marshal.load(session_data)
          rescue
            # Try JSON parsing as fallback
            JSON.parse(session_data)
          end

          return handle_invalid_session("parse failed") unless session.is_a?(Hash)

          # Check if session has identity_id (basic mode marker)
          identity_id = session['identity_id']
          return handle_invalid_session("no identity_id") unless identity_id

          # Skip if already has Rodauth markers
          if session['rodauth_account_id'] && session['rodauth_external_id']
            puts "SKIP (already Rodauth)"
            return
          end

          # Find customer by identity_id
          customer = find_customer(identity_id)
          return handle_customer_not_found(identity_id) unless customer

          # Find linked Rodauth account
          account = find_account_by_extid(customer.extid)
          return handle_account_not_found(customer.extid) unless account

          # Update session with Rodauth information
          update_session(session_key, session, account, customer)

        rescue => e
          puts "ERROR: #{e.message}"
          @logger.error "Failed to process session #{session_key}: #{e.message}"
          @stats[:errors] += 1
        end
      end

      def find_customer(identity_id)
        V2::Customer.load(identity_id)
      rescue
        nil
      end

      def find_account_by_extid(extid)
        @db[:accounts].where(external_id: extid).first
      rescue
        nil
      end

      def update_session(session_key, session, account, customer)
        # Add Rodauth session markers
        updated_session = session.merge(
          'rodauth_account_id' => account[:id],
          'rodauth_external_id' => account[:external_id],
          'authenticated_at' => session['authenticated_at'] || Time.now.to_i
        )

        if @dry_run
          puts "WOULD MIGRATE (account_id: #{account[:id]}, extid: #{account[:external_id]})"
        else
          # Write updated session back to Redis
          serialized = Marshal.dump(updated_session)

          # Preserve original TTL
          ttl = @redis.ttl(session_key)
          if ttl > 0
            @redis.setex(session_key, ttl, serialized)
          else
            @redis.set(session_key, serialized)
          end

          puts "MIGRATED (account_id: #{account[:id]}, extid: #{account[:external_id]})"
        end

        @stats[:sessions_migrated] += 1
      end

      def handle_invalid_session(reason)
        puts "INVALID (#{reason})"
        @stats[:sessions_invalid] += 1
      end

      def handle_customer_not_found(identity_id)
        puts "SKIP (customer not found: #{identity_id})"
        @stats[:customers_not_found] += 1
      end

      def handle_account_not_found(extid)
        puts "SKIP (account not found for extid: #{extid})"
        @stats[:accounts_not_found] += 1
      end

      def print_summary
        puts
        puts "=" * 60
        puts "Session Migration Summary"
        puts "=" * 60
        puts "Sessions found:        #{@stats[:sessions_found]}"
        puts "Sessions migrated:     #{@stats[:sessions_migrated]}"
        puts "Sessions invalid:      #{@stats[:sessions_invalid]}"
        puts "Customers not found:   #{@stats[:customers_not_found]}"
        puts "Accounts not found:    #{@stats[:accounts_not_found]}"
        puts "Errors encountered:    #{@stats[:errors]}"
        puts

        if @dry_run
          puts "This was a DRY RUN. No sessions were modified."
          puts "To perform the actual migration, run with --live flag."
        else
          puts "Session migration completed!"
          puts
          puts "Active sessions now have Rodauth compatibility markers."
          puts "Users will not need to re-authenticate after mode switch."
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
  OT.boot! :test, false

  # Run the session migration
  migration = Onetime::Migrations::PreserveSessionsDuringMigration.new(
    dry_run: options[:dry_run]
  )

  migration.migrate!
end
