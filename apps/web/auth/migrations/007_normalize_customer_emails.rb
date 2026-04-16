# apps/web/auth/migrations/007_normalize_customer_emails.rb
#
# frozen_string_literal: true

# Data migration to normalize customer emails to lowercase in both PostgreSQL
# and Redis. Required for v0.24 environments running full auth mode where
# customers may have been created with mixed-case emails.
#
# PostgreSQL: Updates accounts.email to lowercase (citext preserves queries)
# Redis: Re-keys customer:email_index entries and updates Customer.email field
#
# Safety:
#   - Handles duplicates: logs warning and skips if lowercase key already exists
#   - Idempotent: safe to run multiple times
#   - Dry-run supported via DRY_RUN=1 environment variable
#
# Usage:
#   # Dry run (preview changes)
#   DRY_RUN=1 sequel -m apps/web/auth/migrations -M 7 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Execute migration
#   sequel -m apps/web/auth/migrations -M 7 $AUTH_DATABASE_URL_MIGRATIONS
#
# @see https://github.com/onetimesecret/onetimesecret/issues/2843

Sequel.migration do
  up do
    dry_run = ENV['DRY_RUN'] == '1'
    puts "\n" + ('=' * 60)
    puts 'Email Normalization Migration'
    puts dry_run ? 'MODE: DRY RUN (no changes will be made)' : 'MODE: LIVE'
    puts '=' * 60

    #
    # Phase 1: PostgreSQL accounts table
    #
    puts "\n[Phase 1] PostgreSQL: Normalizing accounts.email to lowercase"

    # Find accounts with mixed-case emails
    mixed_case_accounts = from(:accounts)
      .where(Sequel.lit('email != LOWER(email)'))
      .select(:id, :email)
      .all

    if mixed_case_accounts.empty?
      puts '  No mixed-case emails found in PostgreSQL'
    else
      puts "  Found #{mixed_case_accounts.size} accounts with mixed-case emails"

      # Check for potential duplicates before updating
      duplicates_found = false
      mixed_case_accounts.each do |account|
        lowercase_email = account[:email].downcase
        existing        = from(:accounts)
          .where(Sequel.lit('LOWER(email) = ?', lowercase_email))
          .exclude(id: account[:id])
          .first

        if existing
          puts "  WARNING: Duplicate detected - #{obfuscate_email(account[:email])} conflicts with existing #{obfuscate_email(existing[:email])}"
          duplicates_found = true
        end
      end

      if duplicates_found
        puts '  ERROR: Cannot proceed with PostgreSQL normalization due to duplicates'
        puts '         Resolve duplicate accounts manually before re-running'
      elsif dry_run
        puts '  Would update:'
        mixed_case_accounts.each do |account|
          puts "    #{obfuscate_email(account[:email])} -> #{obfuscate_email(account[:email].downcase)}"
        end
      else
        # Perform the update
        updated_count = from(:accounts)
          .where(Sequel.lit('email != LOWER(email)'))
          .update(email: Sequel.lit('LOWER(email)'))
        puts "  Updated #{updated_count} accounts"
      end
    end

    #
    # Phase 2: Redis customer:email_index
    #
    puts "\n[Phase 2] Redis: Re-keying customer:email_index entries"

    begin
      # Attempt to load Familia for Redis access
      require 'familia'

      redis     = Familia.dbclient
      index_key = 'customer:email_index'

      if redis.exists?(index_key)
        # Scan all entries in the email index
        entries = redis.hgetall(index_key)
        puts "  Found #{entries.size} entries in customer:email_index"

        stats      = { updated: 0, skipped_already_lower: 0, skipped_duplicate: 0, customer_objects_updated: 0 }
        duplicates = []

        entries.each do |email, objid_json|
          lowercase_email = OT::Utils.normalize_email(email)

          if email == lowercase_email
            stats[:skipped_already_lower] += 1
            next
          end

          # Check if lowercase key already exists (duplicate)
          if entries.key?(lowercase_email) || redis.hexists(index_key, lowercase_email)
            duplicates << { original: email, lowercase: lowercase_email, objid: objid_json }
            stats[:skipped_duplicate] += 1
            next
          end

          # Parse objid from JSON (Familia stores values as JSON strings)
          objid = begin
            JSON.parse(objid_json)
          rescue JSON::ParserError
            objid_json  # Fall back to raw value
          end

          customer_key = "customer:#{objid}:object"

          if dry_run
            puts "    Would rekey: #{obfuscate_email(email)} -> #{obfuscate_email(lowercase_email)}"

            # Check if Customer object email also needs updating
            if redis.exists?(customer_key)
              stored_email_raw = redis.hget(customer_key, 'email')
              stored_email     = begin
                Familia::JsonSerializer.parse(stored_email_raw)
              rescue JSON::ParserError, Familia::SerializerError
                stored_email_raw
              end
              if stored_email && stored_email != lowercase_email
                puts "      Would update Customer object: #{obfuscate_email(stored_email)} -> #{obfuscate_email(lowercase_email)}"
                stats[:customer_objects_updated] += 1
              end
            end
          else
            # Atomic rekey: set lowercase, delete mixed-case
            redis.multi do |tx|
              tx.hset(index_key, lowercase_email, objid_json)
              tx.hdel(index_key, email)
            end

            # Also update the email field on the Customer object in Redis
            if redis.exists?(customer_key)
              stored_email_raw = redis.hget(customer_key, 'email')
              stored_email     = begin
                Familia::JsonSerializer.parse(stored_email_raw)
              rescue JSON::ParserError, Familia::SerializerError
                stored_email_raw
              end
              if stored_email && stored_email != lowercase_email
                redis.hset(customer_key, 'email', Familia::JsonSerializer.dump(lowercase_email))
                stats[:customer_objects_updated] += 1
              end
            end
          end

          stats[:updated] += 1
        end

        puts "\n  Results:"
        puts "    Already lowercase: #{stats[:skipped_already_lower]}"
        puts "    #{dry_run ? 'Would rekey' : 'Rekeyed'}: #{stats[:updated]}"
        puts "    Customer objects #{dry_run ? 'would update' : 'updated'}: #{stats[:customer_objects_updated]}"
        puts "    Skipped (duplicates): #{stats[:skipped_duplicate]}"

        if duplicates.any?
          puts "\n  WARNING: Duplicate entries detected (not migrated):"
          duplicates.each do |dup|
            puts "    #{obfuscate_email(dup[:original])} -> #{obfuscate_email(dup[:lowercase])} (objid: #{dup[:objid][0..15]}...)"
          end
          puts '  Resolve these manually by choosing which account to keep'
        end
      else
        puts '  customer:email_index does not exist - skipping Redis phase'
      end
    rescue LoadError => ex
      puts "  Skipping Redis phase: Familia not available (#{ex.message})"
      puts '  Run Redis normalization separately using:'
      puts '    bin/ots migrations normalize-customer-emails --run'
    rescue Redis::CannotConnectError => ex
      puts "  Skipping Redis phase: Cannot connect to Redis (#{ex.message})"
    end

    puts "\n" + ('=' * 60)
    if dry_run
      puts 'DRY RUN COMPLETE - No changes were made'
      puts 'To execute migration, run without DRY_RUN=1'
    else
      puts 'Migration complete'
    end
    puts ('=' * 60) + "\n"
  end

  down do
    # Email normalization is a one-way data migration.
    # Rolling back would require restoring original mixed-case values from backup.
    puts "\n[WARNING] Email normalization cannot be automatically reversed."
    puts 'Original mixed-case email values are not preserved.'
    puts 'To restore, use a database backup from before the migration.'
    puts ''
  end
end

# Helper method for obfuscating email in logs
def obfuscate_email(email)
  return '***' unless email.is_a?(String) && email.include?('@')

  local, domain = email.split('@', 2)
  "#{local[0..2]}***@#{domain&.sub(/\A[^.]+/, '***') || '***'}"
end
