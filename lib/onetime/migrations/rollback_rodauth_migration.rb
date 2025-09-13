#!/usr/bin/env ruby
# lib/onetime/migrations/rollback_rodauth_migration.rb
#
# Rollback procedures for Otto's Derived Identity Architecture.
# Safely reverts from Rodauth mode back to basic (Redis-only) mode.

require 'bundler/setup'
require 'familia'
require 'sequel'
require_relative '../auth_config'

module Onetime
  module Migrations
    class RollbackRodauthMigration
      attr_reader :config, :db, :redis, :stats

      def initialize(dry_run: true)
        @dry_run = dry_run
        @config = Onetime.auth_config
        @stats = {
          sessions_found: 0,
          sessions_cleaned: 0,
          sessions_preserved: 0,
          errors: 0
        }

        setup_connections
        setup_logging
      end

      def rollback!
        puts "=" * 60
        puts "OneTimeSecret: Rodauth Migration Rollback"
        puts "=" * 60
        puts "Mode: #{@dry_run ? 'DRY RUN' : 'LIVE ROLLBACK'}"
        puts "Time: #{Time.now}"
        puts

        puts "⚠️  WARNING: This will revert authentication back to basic (Redis-only) mode."
        puts "⚠️  Rodauth accounts will remain in the database but will not be used."
        puts "⚠️  Users may need to re-authenticate if sessions are cleared."
        puts

        unless @dry_run
          print "Are you sure you want to proceed? (type 'rollback' to confirm): "
          response = $stdin.gets.chomp
          unless response == 'rollback'
            puts "Rollback cancelled."
            exit 0
          end
        end

        validate_preconditions!
        clean_rodauth_session_markers
        print_rollback_instructions
        print_summary
      end

      private

      def setup_connections
        # Setup Redis connection (Familia)
        Familia.uri = @config.session['redis_url'] || 'redis://localhost:6379/0'
        @redis = Familia.dbclient

        # Setup database connection if available
        begin
          @db = Sequel.connect(@config.database_url)
        rescue
          @db = nil
          puts "Database connection not available (OK for rollback)"
        end
      end

      def setup_logging
        @logger = Logger.new($stdout)
        @logger.level = @dry_run ? Logger::INFO : Logger::WARN
      end

      def validate_preconditions!
        # Check Redis connection
        @redis.ping
        puts "✓ Redis connection established"

        puts "✓ Pre-conditions validated"
        puts
      end

      def clean_rodauth_session_markers
        puts "Cleaning Rodauth markers from Redis sessions..."

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
          return handle_no_data unless session_data

          # Parse session data
          session = begin
            Marshal.load(session_data)
          rescue
            begin
              JSON.parse(session_data)
            rescue
              return handle_parse_error
            end
          end

          return handle_invalid_session unless session.is_a?(Hash)

          # Check if session has Rodauth markers
          has_rodauth_markers = session.key?('rodauth_account_id') ||
                               session.key?('rodauth_external_id') ||
                               session.key?('authenticated_at')

          unless has_rodauth_markers
            puts "SKIP (no Rodauth markers)"
            @stats[:sessions_preserved] += 1
            return
          end

          # Clean session by removing Rodauth-specific keys
          clean_session(session_key, session)

        rescue => e
          puts "ERROR: #{e.message}"
          @logger.error "Failed to process session #{session_key}: #{e.message}"
          @stats[:errors] += 1
        end
      end

      def clean_session(session_key, session)
        # Remove Rodauth-specific keys while preserving basic auth session
        cleaned_session = session.dup

        # Remove Rodauth markers
        cleaned_session.delete('rodauth_account_id')
        cleaned_session.delete('rodauth_external_id')

        # Keep authenticated_at if it existed before (might be used by basic auth)
        # Remove it only if it was likely added by Rodauth

        # Keep identity_id (used by basic mode)
        # Keep other session data

        if @dry_run
          puts "WOULD CLEAN (removing Rodauth markers)"
        else
          # Write cleaned session back to Redis
          serialized = Marshal.dump(cleaned_session)

          # Preserve original TTL
          ttl = @redis.ttl(session_key)
          if ttl > 0
            @redis.setex(session_key, ttl, serialized)
          else
            @redis.set(session_key, serialized)
          end

          puts "CLEANED (Rodauth markers removed)"
        end

        @stats[:sessions_cleaned] += 1
      end

      def handle_no_data
        puts "SKIP (no data)"
        @stats[:sessions_preserved] += 1
      end

      def handle_parse_error
        puts "SKIP (parse error)"
        @stats[:sessions_preserved] += 1
      end

      def handle_invalid_session
        puts "SKIP (invalid format)"
        @stats[:sessions_preserved] += 1
      end

      def print_rollback_instructions
        puts
        puts "=" * 60
        puts "Manual Rollback Steps Required"
        puts "=" * 60
        puts
        puts "1. Update configuration:"
        puts "   Edit config/authentication.yml:"
        puts "   authentication:"
        puts "     mode: basic  # Change from 'rodauth' to 'basic'"
        puts
        puts "2. Restart the application to pick up new configuration"
        puts
        puts "3. Optional: Remove Rodauth database (if no longer needed):"
        puts "   rm data/auth.db"
        puts "   # Or keep it for future migration attempts"
        puts
        puts "4. Verify authentication works in basic mode"
        puts
      end

      def print_summary
        puts "=" * 60
        puts "Rollback Summary"
        puts "=" * 60
        puts "Sessions found:     #{@stats[:sessions_found]}"
        puts "Sessions cleaned:   #{@stats[:sessions_cleaned]}"
        puts "Sessions preserved: #{@stats[:sessions_preserved]}"
        puts "Errors encountered: #{@stats[:errors]}"
        puts

        if @dry_run
          puts "This was a DRY RUN. No sessions were modified."
          puts "To perform the actual rollback, run with --live flag."
        else
          puts "Session cleanup completed!"
          puts
          puts "⚠️  IMPORTANT: You must still manually update the configuration"
          puts "   and restart the application to complete the rollback."
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

    opts.on("--live", "Perform actual rollback (default: dry run)") do
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

  # Load minimal environment for rollback
  require_relative '../../../lib/onetime'

  # Setup Familia without full boot
  require 'familia'

  # Run the rollback
  rollback = Onetime::Migrations::RollbackRodauthMigration.new(
    dry_run: options[:dry_run]
  )

  rollback.rollback!
end
