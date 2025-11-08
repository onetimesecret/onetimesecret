# lib/onetime/cli/sync_auth_accounts_command.rb
#
# frozen_string_literal: true

#
# Synchronizes customer records from Redis to Auth application SQL database.
# Primary use case: Switching from auth mode=basic to mode=advanced.
#
# This command creates account records in the Rodauth database for existing
# customers in Redis, linking them via external_id for future synchronization.

module Onetime
  class SyncAuthAccountsCommand < Onetime::CLI
    def sync_auth_accounts
      return if show_usage_help

      # Check that advanced mode is enabled
      unless Onetime.auth_config.advanced_enabled?
        puts <<~MESSAGE

          ⚠️  Advanced auth mode is not enabled.

          This command is only useful when switching from basic to advanced mode.
          Please set authentication.mode to 'advanced' in your config or use:

            AUTHENTICATION_MODE=advanced bin/ots sync-auth-accounts

        MESSAGE
        return
      end

      # Require database connection
      db = Auth::Database.connection
      unless db
        puts <<~MESSAGE

          ❌ Could not connect to Auth database.

          Please ensure your database configuration is correct:
          - DATABASE_URL environment variable, or
          - authentication.database_url in config file

        MESSAGE
        return
      end

      puts "\nAuth Account Synchronization Tool"
      puts '=' * 60

      # Get all customers from Redis (Familia v2 pattern)
      all_customer_ids = Onetime::Customer.instances.all
      total_customers = all_customer_ids.size

      puts "\nDiscovered #{total_customers} customers in Redis"

      # Check for dry-run mode
      dry_run = !option.run
      if dry_run
        puts "\nDRY RUN MODE - No changes will be made"
        puts "To execute synchronization, run with --run flag\n"
      end

      # Track statistics
      stats = {
        total: 0,
        skipped_anonymous: 0,
        skipped_existing: 0,
        created: 0,
        linked: 0,
        errors: []
      }

      # Process each customer
      all_customer_ids.each_with_index do |custid, idx|
        stats[:total] += 1

        begin
          customer = Onetime::Customer.load(custid)

          # Skip anonymous customers (they shouldn't be in auth DB)
          if customer.anonymous?
            stats[:skipped_anonymous] += 1
            if global.verbose > 0
              puts "  [#{idx+1}/#{total_customers}] Skipping anonymous: #{customer.custid}"
            end
            next
          end

          # Check if account already exists by email
          existing_account = db[:accounts]
            .where(email: customer.email)
            .where(status_id: [1, 2])  # Only active accounts
            .first

          if existing_account
            # Account exists - verify/update external_id link if needed
            if existing_account[:external_id] == customer.extid
              stats[:skipped_existing] += 1
              if global.verbose > 1
                puts "  [#{idx+1}/#{total_customers}] ✓ Already synced: #{obscure_email(customer.email)} (#{existing_account[:id]})"
              end
            else
              # Account exists but external_id needs updating
              if dry_run
                puts "  [#{idx+1}/#{total_customers}] Would link account #{existing_account[:id]} → extid #{customer.extid}"
                stats[:linked] += 1
              else
                db[:accounts]
                  .where(id: existing_account[:id])
                  .update(external_id: customer.extid, updated_at: Sequel::CURRENT_TIMESTAMP)
                stats[:linked] += 1
                if global.verbose > 0
                  puts "  [#{idx+1}/#{total_customers}] ↔ Linked: #{obscure_email(customer.email)} → extid #{customer.extid}"
                end
              end
            end
          else
            # Account doesn't exist - create it
            if dry_run
              puts "  [#{idx+1}/#{total_customers}] Would create: #{obscure_email(customer.email)}"
              stats[:created] += 1
            else
              # Determine status based on customer state
              status_id = customer.verified? ? 2 : 1  # 2=Verified, 1=Unverified

              # Create account using raw SQL to match Rodauth schema
              account_id = db[:accounts].insert(
                email: customer.email,
                external_id: customer.extid,
                status_id: status_id,
                created_at: Sequel::CURRENT_TIMESTAMP,
                updated_at: Sequel::CURRENT_TIMESTAMP
              )

              stats[:created] += 1
              if global.verbose > 0
                puts "  [#{idx+1}/#{total_customers}] ✓ Created: #{obscure_email(customer.email)} (#{account_id})"
              end
            end
          end

          # Progress indicator for non-verbose mode
          if global.verbose == 0 && (stats[:total] % 10 == 0)
            print "\r  Progress: #{stats[:total]}/#{total_customers} customers processed"
          end

        rescue => ex
          error_msg = "#{obscure_email(customer&.email || custid)}: #{ex.message}"
          stats[:errors] << error_msg

          puts "  [#{idx+1}/#{total_customers}] ❌ Error: #{error_msg}"
          OT.le "Sync error for #{custid}: #{ex.message}"
          OT.ld ex.backtrace.join("\n") if global.verbose > 1
        end
      end

      # Clear progress line
      print "\r" + (' ' * 80) + "\r" if global.verbose == 0

      # Report results
      puts "\n" + ('=' * 60)
      puts "Synchronization #{dry_run ? 'Preview' : 'Complete'}"
      puts '=' * 60
      puts "\nStatistics:"
      puts "  Total customers:     #{stats[:total]}"
      puts "  Skipped (anonymous): #{stats[:skipped_anonymous]}"
      puts "  Skipped (existing):  #{stats[:skipped_existing]}"
      puts "  Linked:              #{stats[:linked]}"
      puts "  Created:             #{stats[:created]}"

      if stats[:errors].any?
        puts "\n  Errors:              #{stats[:errors].size}"
        if global.verbose > 0
          puts "\n  Error details:"
          stats[:errors].each { |err| puts "    • #{err}" }
        end
      end

      if dry_run
        puts <<~MESSAGE

          To execute synchronization, run:
            bin/ots sync-auth-accounts --run

        MESSAGE
      else
        puts <<~MESSAGE

          ✅ Synchronization complete!

          Next steps:
          1. Verify accounts in database: sqlite3 data/auth.db "SELECT COUNT(*) FROM accounts;"
          2. Test login with existing credentials
          3. Update authentication.mode to 'advanced' in config if not already set

        MESSAGE
      end
    end

    private

    def obscure_email(email)
      return 'anonymous' if email.to_s.empty?
      OT::Utils.obscure_email(email)
    end

    def show_usage_help
      if option.help
        puts <<~USAGE

          Auth Account Synchronization Tool

          Usage:
            bin/ots sync-auth-accounts [options]

          Description:
            Synchronizes customer records from Redis to the Auth SQL database.
            Creates account records for existing customers, enabling migration
            from basic auth mode to advanced (Rodauth) auth mode.

          Options:
            --run                 Execute synchronization (required for actual operation)
            --dry-run             Show what would be synchronized without executing (default)
            --verbose, -v         Show detailed progress for each customer
            --help, -h            Show this help message

          Examples:
            # Preview synchronization
            bin/ots sync-auth-accounts

            # Execute synchronization
            bin/ots sync-auth-accounts --run

            # Execute with detailed progress
            bin/ots sync-auth-accounts --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips anonymous customers automatically
            - Links existing accounts via external_id if found
            - Creates new accounts with appropriate status (verified/unverified)
            - Requires advanced auth mode to be enabled

        USAGE
        true
      end
    end
  end
end
