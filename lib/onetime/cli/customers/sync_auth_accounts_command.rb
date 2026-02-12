# lib/onetime/cli/customers/sync_auth_accounts_command.rb
#
# frozen_string_literal: true

#
# Synchronizes customer records from Redis to Auth application SQL database.
# Primary use case: Switching from auth mode=simple to mode=full.
#
# This command creates account records in the Rodauth database for existing
# customers in Redis, linking them via external_id for future synchronization.
#
# PREREQUISITE: Familia v1→v2 migration must be complete
#
# This command expects customers to be in Redis DB 0 with populated indexes
# (Familia v2 layout). If you're running Familia v1 (customers in DB 6),
# you must first run the data migration:
#
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/pipeline.rb      # Transform data
#   bundle exec ruby jobs/06_load.rb       # Load to DB 0
#
# The command uses Customer.instances (a sorted set index) to enumerate all
# customers. This index is only populated in Familia v2 when customers are
# saved with the :object_identifier feature enabled.

module Onetime
  module CLI
    class SyncAuthAccountsCommand < Command
      BATCH_SIZE = 1000

      desc 'Synchronize customer records from Redis to Auth SQL database'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute synchronization (required for actual operation)'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each customer'

      def call(run: false, help: false, verbose: false, **)
        return show_usage_help if help

        boot_application!

        # Check that full mode is enabled
        unless Onetime.auth_config.full_enabled?
          puts <<~MESSAGE

            ⚠️  Full auth mode is not enabled.

            This command is only useful when switching from simple to full mode.
            Please set authentication.mode to 'full' in your config or use:

              AUTHENTICATION_MODE=full bin/ots customers sync-auth-accounts

          MESSAGE
          return
        end

        # Require database connection
        db = Auth::Database.connection
        unless db
          puts <<~MESSAGE

            ❌ Could not connect to Auth database.

            Please ensure your database configuration is correct:
            - AUTH_DATABASE_URL environment variable, or
            - authentication.database_url in config file

          MESSAGE
          return
        end

        puts "\nAuth Account Synchronization Tool"
        puts '=' * 60

        # Get all customers from Redis (Familia v2 pattern)
        # The instances sorted set is populated by the :object_identifier feature
        all_customer_ids = Onetime::Customer.instances.all
        total_customers  = all_customer_ids.size

        if total_customers.zero?
          puts <<~MESSAGE

            ⚠️  No customers found in Redis DB 0.

            This command requires the Familia v1→v2 migration to be complete.
            Customer data must be in DB 0 with populated indexes.

            If customers exist in legacy databases (DB 6/7/8), run the migration first:

              cd migrations/2026-01-28
              bundle exec ruby jobs/pipeline.rb      # Transform data
              bundle exec ruby jobs/06_load.rb       # Load to DB 0

          MESSAGE
          return
        end

        puts "\nDiscovered #{total_customers} customers in Redis"

        # Check for dry-run mode
        dry_run = !run
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "To execute synchronization, run with --run flag\n"
        end

        # Build skip set from already-synced accounts for resume capability
        existing_extids = Set.new(
          db[:accounts]
            .where(Sequel.~(external_id: nil))
            .select_map(:external_id),
        )
        puts "Found #{existing_extids.size} existing accounts (will skip)"

        # Track statistics
        stats = {
          total: 0,
          skipped_anonymous: 0,
          skipped_system: 0,
          skipped_existing: 0,
          created: 0,
          linked: 0,
          errors: [],
        }

        # Verbose level (0 = none, 1 = some, 2+ = all details)
        verbose_level = verbose ? 1 : 0

        # Process customers in batches
        # NOTE: instances.all returns objids (the identifier_field for Customer)
        all_customer_ids.each_slice(BATCH_SIZE).with_index do |batch_ids, batch_idx|
          batch_start = batch_idx * BATCH_SIZE
          process_batch(db, batch_ids, batch_start, existing_extids, stats, verbose_level, total_customers, dry_run)
        end

        # Clear progress line
        print "\r" + (' ' * 80) + "\r" if verbose_level == 0

        # Report results
        puts "\n" + ('=' * 60)
        puts "Synchronization #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Total customers:     #{stats[:total]}"
        puts "  Skipped (anonymous): #{stats[:skipped_anonymous]}"
        puts "  Skipped (system):    #{stats[:skipped_system]}"
        puts "  Skipped (existing):  #{stats[:skipped_existing]}"
        puts "  Linked:              #{stats[:linked]}"
        puts "  Created:             #{stats[:created]}"

        if stats[:errors].any?
          puts "\n  Errors:              #{stats[:errors].size}"
          if verbose_level > 0
            puts "\n  Error details:"
            stats[:errors].each { |err| puts "    • #{err}" }
          end
        end

        if dry_run
          puts <<~MESSAGE

            To execute synchronization, run:
              bin/ots customers sync-auth-accounts --run

          MESSAGE
        else
          puts <<~MESSAGE

            ✅ Synchronization complete!

            Next steps:
            1. Verify accounts in database using your DB client
               Example: SELECT COUNT(*) FROM accounts;
            2. Test login with existing credentials
            3. Update authentication.mode to 'full' in config if not already set

          MESSAGE
        end
      end

      private

      def process_batch(db, batch_ids, batch_start, existing_extids, stats, verbose_level, total, dry_run)
        batch_processed_extids = []

        db.transaction do
          batch_ids.each_with_index do |objid, idx|
            global_idx     = batch_start + idx
            stats[:total] += 1

            customer = Onetime::Customer.load(objid)

            # Skip anonymous customers (they shouldn't be in auth DB)
            if customer.anonymous?
              stats[:skipped_anonymous] += 1
              puts "  [#{global_idx+1}/#{total}] Skipping anonymous: #{customer.custid}" if verbose_level > 0
              next
            end

            # Skip system customers (GLOBAL, etc.) - check both custid and email
            # because migrated data may have GLOBAL as the email value
            if customer.global? || customer.email.to_s.upcase == 'GLOBAL'
              stats[:skipped_system] += 1
              puts "  [#{global_idx+1}/#{total}] Skipping system: #{customer.custid}" if verbose_level > 0
              next
            end

            # Skip customers without valid email format
            unless customer.email.to_s.include?('@')
              stats[:skipped_system] += 1
              puts "  [#{global_idx+1}/#{total}] Skipping invalid email: #{customer.email}" if verbose_level > 0
              next
            end

            # Skip already-synced (resume support)
            if existing_extids.include?(customer.extid)
              stats[:skipped_existing] += 1
              puts "  [#{global_idx+1}/#{total}] Already synced: #{obscure_email(customer.email)}" if verbose_level > 1
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
                if verbose_level > 1
                  puts "  [#{global_idx+1}/#{total}] ✓ Already synced: #{obscure_email(customer.email)} (#{existing_account[:id]})"
                end
              elsif dry_run
                puts "  [#{global_idx+1}/#{total}] Would link account #{existing_account[:id]} → extid #{customer.extid}"
                stats[:linked] += 1
              else
                db[:accounts]
                  .where(id: existing_account[:id])
                  .update(external_id: customer.extid, updated_at: Sequel::CURRENT_TIMESTAMP)
                stats[:linked] += 1
                if verbose_level > 0
                  puts "  [#{global_idx+1}/#{total}] ↔ Linked: #{obscure_email(customer.email)} → extid #{customer.extid}"
                end
                batch_processed_extids << customer.extid
              end
            elsif dry_run
              puts "  [#{global_idx+1}/#{total}] Would create: #{obscure_email(customer.email)}"
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
                updated_at: Sequel::CURRENT_TIMESTAMP,
              )

              stats[:created] += 1
              if verbose_level > 0
                puts "  [#{global_idx+1}/#{total}] ✓ Created: #{obscure_email(customer.email)} (#{account_id})"
              end
              batch_processed_extids << customer.extid
            end

            # Progress indicator for non-verbose mode
            if verbose_level == 0 && (stats[:total] % 100 == 0)
              print "\r  Progress: #{stats[:total]}/#{total} customers processed"
            end
          end
        end

        # Transaction succeeded — update skip set for subsequent batches
        existing_extids.merge(batch_processed_extids)

        # Batch progress
        batch_num     = (batch_start / BATCH_SIZE) + 1
        total_batches = (total.to_f / BATCH_SIZE).ceil
        puts "  Batch #{batch_num}/#{total_batches} committed (#{batch_processed_extids.size} records)" if verbose_level > 0
      rescue Sequel::Error => ex
        batch_num = (batch_start / BATCH_SIZE) + 1
        puts "\nBatch #{batch_num} failed at offset #{batch_start}:"
        puts "  Error: #{ex.message}"
        puts "  Last processed: #{batch_processed_extids&.last || 'none'}"
        puts "\nTo resume, re-run the command. Already-synced records will be skipped."
        raise
      end

      def obscure_email(email)
        return 'anonymous' if email.to_s.empty?

        OT::Utils.obscure_email(email)
      end

      def show_usage_help
        puts <<~USAGE

          Auth Account Synchronization Tool

          Usage:
            bin/ots customers sync-auth-accounts [options]

          Description:
            Synchronizes customer records from Redis to the Auth SQL database.
            Creates account records for existing customers, enabling migration
            from simple auth mode to full (Rodauth) auth mode.

          Options:
            --run                 Execute synchronization (required for actual operation)
            --dry-run             Show what would be synchronized without executing (default)
            --verbose, -v         Show detailed progress for each customer
            --help, -h            Show this help message

          Examples:
            # Preview synchronization
            bin/ots customers sync-auth-accounts

            # Execute synchronization
            bin/ots customers sync-auth-accounts --run

            # Execute with detailed progress
            bin/ots customers sync-auth-accounts --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips anonymous customers automatically
            - Links existing accounts via external_id if found
            - Creates new accounts with appropriate status (verified/unverified)
            - Requires full auth mode to be enabled

        USAGE
        true
      end
    end

    register 'customers sync-auth-accounts', SyncAuthAccountsCommand
  end
end
