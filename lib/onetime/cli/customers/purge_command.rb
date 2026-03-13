# lib/onetime/cli/customers/purge_command.rb
#
# frozen_string_literal: true

# Purge inactive customer records by last activity date.
# Uses last_login (preferred) or updated (fallback) to determine activity.
#
# SAFETY: Customers associated with Stripe billing (via their Organization
# or via deprecated v1 fields) are NEVER purged, regardless of inactivity.
#
# Workflow:
#   1. Run dry-run first to review candidates and cache them
#   2. Run again with --purge to execute (reuses cached candidate set)
#   3. Each customer.destroy! removes object hash + all indexes + metadata
#
# Operational notes:
#   - BGSAVE Redis before running --purge on production
#   - Run during off-peak hours for large purges (1000+ records)
#   - Candidates are cached for 30 minutes; --purge reuses the same set
#   - Process runs in batches of 50 with progress tracking
#   - Every deletion is logged via OT.info for audit trail
#   - Consider exporting affected customer emails before purging
#
# Usage:
#   bin/ots customers purge --older-than 3y              # Dry run
#   bin/ots customers purge --older-than 3y --purge      # Execute
#   bin/ots customers purge --older-than 5y --refresh    # Force rescan

module Onetime
  module CLI
    class CustomersPurgeCommand < Command # rubocop:disable Metrics/ClassLength
      include Customers::Shared

      desc 'Purge inactive customer records by last activity date'

      ACTIVITY_CACHE = 'tmp:cli:cust_by_activity'
      CREATED_CACHE  = 'tmp:cli:cust_by_created'
      # Purge batch size; 50 balances throughput with progress visibility
      # while allowing frequent progress output to the console.
      BATCH_SIZE     = 50

      # Sub-keys to delete when purging a customer directly from Redis.
      CUSTOMER_SUB_KEYS = %w[object metadata receipts reset_secret
                             pending_email_change pending_email_delivery_status
                             feature_flags].freeze

      option :older_than,
        type: :string,
        default: nil,
        desc: 'Activity age threshold (e.g., 6m, 1y, 2y, 3y, 5y)'

      option :purge,
        type: :boolean,
        default: false,
        desc: 'Execute purge (default is dry-run)'

      option :refresh,
        type: :boolean,
        default: false,
        desc: 'Force cache rebuild before selecting candidates'

      option :redis_url,
        type: :string,
        default: nil,
        desc: 'Redis/Valkey URL to scan (e.g., redis://host:6379/6)'

      def call(older_than: nil, purge: false, refresh: false, redis_url: nil, **)
        unless older_than
          show_usage
          return
        end

        boot_application!

        cache_redis   = Familia.dbclient
        source_redis  = redis_url ? redis_client_from_url(redis_url) : cache_redis
        @using_remote = !redis_url.nil?

        if @using_remote
          puts "Source: #{redact_url(redis_url)}"
          puts 'Cache:  configured db (temp keys)'
          puts
        end

        threshold_secs = parse_duration(older_than)
        cutoff         = Time.now - threshold_secs
        cutoff_epoch   = cutoff.to_f

        if refresh
          cache_redis.del(ACTIVITY_CACHE, CREATED_CACHE)
          puts 'Cache cleared.'
        end

        ensure_cache(
          source_redis,
          cache_redis,
          primary_key: ACTIVITY_CACHE,
          cache_keys: [ACTIVITY_CACHE, CREATED_CACHE],
        )

        # Get candidates: all objids with last activity before cutoff
        candidates = cache_redis.zrangebyscore(ACTIVITY_CACHE, '-inf', cutoff_epoch.to_s)

        puts "Purge candidates: #{candidates.size} customers inactive since #{cutoff.strftime('%Y-%m-%d')}"
        puts 'Activity source: last_login (preferred) or updated (fallback)'
        puts

        if candidates.empty?
          puts 'No customers match the criteria.'
          return
        end

        if purge
          execute_purge(source_redis, cache_redis, candidates, cutoff)
        else
          show_dry_run(source_redis, candidates, older_than)
        end
      rescue ArgumentError => ex
        puts ex.message
      end

      private

      def show_usage
        puts <<~USAGE
          Usage: bin/ots customers purge --older-than DURATION [options]

          Duration: 6m, 12m, 18m (30-day months) | 1y, 2y, 3y, 5y (365-day years)

          Options:
            --older-than DURATION   Activity age threshold (required)
            --purge                 Execute deletion (default is dry-run)
            --refresh               Force cache rebuild before selecting
            --redis-url URL         Scan a different Redis (e.g., pre-migration db=6)

          Examples:
            bin/ots customers purge --older-than 3y              # Preview
            bin/ots customers purge --older-than 3y --purge      # Execute
            bin/ots customers purge --older-than 5y --redis-url redis://host:6379/6

          Dry-run caches candidates for 30 minutes. Running --purge within that
          window reuses the same set. When --redis-url is used, purge deletes
          keys directly via DEL (no model loading, no index cleanup).
        USAGE
      end

      def show_dry_run(source_redis, candidates, duration)
        puts 'DRY RUN - No records will be modified'
        puts

        purgeable_count   = 0
        billing_protected = 0
        no_load           = 0
        shown             = 0

        candidates.each do |objid|
          record = load_customer_record(source_redis, objid)
          unless record
            no_load += 1
            next
          end

          if record[:billing_protected]
            billing_protected += 1
            next
          end

          purgeable_count += 1

          if shown < 20
            puts format('  %-36s %s=%-10s %s', objid, record[:source], record[:date], record[:email])
            shown += 1
          end
        end

        if purgeable_count > 20
          puts "  ... and #{purgeable_count - 20} more"
        end

        puts
        if billing_protected > 0
          puts "  Stripe-protected: #{billing_protected} (have billing association, will NOT be purged)"
        end
        if no_load > 0
          puts "  Not loadable:     #{no_load} (may already be deleted)"
        end
        puts "  Purgeable:        #{purgeable_count}"

        puts
        puts '-' * 60
        puts 'BEFORE PURGING:'
        puts '  1. Back up Redis: redis-cli BGSAVE'
        puts '  2. Export affected emails if needed for notification'
        puts "  3. Run during off-peak hours for large sets (#{purgeable_count} records)"
        puts '  4. Each destroy! removes: object hash, indexes, metadata, relationships'
        puts '  5. This action is NOT reversible without a Redis backup'
        puts
        puts 'NOTE: If running in full auth mode, corresponding SQL accounts'
        puts '  in the auth database are NOT removed by this command. Clean'
        puts '  up orphaned accounts separately if needed.'
        puts
        puts 'To execute:'
        puts "  bin/ots customers purge --older-than #{duration} --purge"
      end

      def execute_purge(source_redis, cache_redis, candidates, cutoff)
        # Verify cache is still populated before executing destructive operation
        cache_size = cache_redis.zcard(ACTIVITY_CACHE)
        if cache_size.zero?
          puts 'Cache expired. Re-run without --purge to rebuild candidate list.'
          return
        end

        if cache_size != candidates.size
          puts "WARNING: Cache size (#{cache_size}) differs from candidate count (#{candidates.size})."
          puts 'Cache may have been modified. Re-run without --purge to rebuild.'
          return
        end

        total             = candidates.size
        destroyed         = 0
        skipped           = 0
        billing_protected = 0
        errors            = []

        puts "PURGING #{total} candidates inactive since #{cutoff.strftime('%Y-%m-%d')}..."
        puts '(Customers with Stripe billing will be skipped automatically)'
        if @using_remote
          puts '(Deleting keys directly from source via DEL)'
        end
        puts

        candidates.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
          # Batch-load customer records to avoid N+1 Redis round-trips.
          # For local mode, uses Familia's load_multi (single pipeline).
          # For remote mode, load_customer_record already does individual
          # HMGET calls; batching at this level keeps the slice structure
          # consistent and bounds the working set to BATCH_SIZE.
          records_by_id = batch_load_customer_records(source_redis, batch)
          destroyed_ids = []

          batch.each do |objid|
            record = records_by_id[objid]
            unless record
              skipped += 1
              next
            end

            if record[:billing_protected]
              billing_protected += 1
              OT.info "[purge] Protected (billing): #{objid} #{record[:email]}"
              next
            end

            begin
              if @using_remote
                # Direct key deletion on remote source (no model, no indexes to clean)
                delete_customer_keys(source_redis, objid)
              else
                cust = record[:_model]
                unless cust
                  skipped += 1
                  next
                end
                cust.destroy!
              end

              destroyed_ids << objid
              destroyed += 1
              OT.info "[purge] Destroyed #{objid} #{record[:email]}"
            rescue StandardError => ex
              errors << "#{objid}: #{ex.message}"
              OT.le "[purge] Error destroying #{objid}: #{ex.message}"
            end
          end

          # Batch zrem: remove all destroyed IDs from cache in one call
          # per sorted set, rather than one zrem per customer.
          if destroyed_ids.any?
            cache_redis.zrem(ACTIVITY_CACHE, destroyed_ids)
            cache_redis.zrem(CREATED_CACHE, destroyed_ids)
          end

          processed = (batch_idx + 1) * BATCH_SIZE
          processed = [processed, total].min
          print "\r  Progress: #{processed}/#{total} (#{destroyed} destroyed, #{billing_protected} billing-protected, #{skipped} skipped)"
        end

        print "\r" + (' ' * 80) + "\r"
        puts
        puts 'Purge complete'
        puts '-' * 30
        puts "  Destroyed:         #{destroyed}"
        puts "  Billing-protected: #{billing_protected}"
        puts "  Skipped:           #{skipped}"
        puts "  Errors:            #{errors.size}"

        return unless errors.any?

        puts
        puts '  Error details:'
        errors.first(20).each { |e| puts "    #{e}" }
        puts "    ... and #{errors.size - 20} more" if errors.size > 20
      end

      def build_cache(source_redis, cache_redis)
        puts 'Scanning customer records for activity dates...'

        # Phase 1: Collect keys via SCAN (from source)
        keys = []
        source_redis.scan_each(match: 'customer:*:object', count: SCAN_COUNT) do |key|
          keys << key
        end

        # Fallback to instances index (only when scanning local db)
        if keys.empty? && !@using_remote
          puts '  No customer:*:object keys found. Using instances index...'
          count, skipped = build_cache_from_instances(cache_redis)
          finalize_cache(
            cache_redis,
            count,
            skipped,
            cache_keys: [ACTIVITY_CACHE, CREATED_CACHE],
            skip_label: 'without activity date',
          )
          return
        elsif keys.empty?
          puts '  No customer:*:object keys found in source.'
          return
        end

        puts "  Found #{keys.size} keys. Reading timestamps..."

        # Phase 2: Pipeline HMGET (read from source, write cache locally)
        count   = 0
        skipped = 0

        keys.each_slice(PIPELINE_BATCH) do |batch|
          results = source_redis.pipelined do |pipe|
            batch.each do |key|
              pipe.hmget(key, 'created', 'updated', 'last_login', 'role', 'email')
            end
          end

          batch.zip(results).each do |key, fields|
            created_raw, updated_raw, last_login_raw, role_raw, email_raw = fields

            role = parse_json_field(role_raw)
            next if role == 'anonymous'

            email = parse_json_field(email_raw)
            next unless email.to_s.match?(/\A[^@\s]+@[^@\s]+\z/)

            objid = key.split(':')[1]

            last_login = parse_ts(last_login_raw)
            updated    = parse_ts(updated_raw)
            activity   = [last_login, updated].select { |t| t > 0 }.max

            if activity && activity > 0
              cache_redis.zadd(ACTIVITY_CACHE, activity, objid)
              count += 1
            else
              skipped += 1
            end

            created = parse_ts(created_raw)
            cache_redis.zadd(CREATED_CACHE, created, objid) if created > 0
          end
        end

        finalize_cache(
          cache_redis,
          count,
          skipped,
          cache_keys: [ACTIVITY_CACHE, CREATED_CACHE],
          skip_label: 'without activity date',
        )
      end

      def build_cache_from_instances(cache_redis)
        count   = 0
        skipped = 0
        # NOTE: Loads all customer identifiers into memory. Acceptable for
        # operational CLI (run infrequently). Would need cursor-based iteration
        # (ZSCAN) for datasets exceeding available memory.
        all_ids = Onetime::Customer.instances.all
        total   = all_ids.size

        puts "  Loading #{total} customers from instances index..."

        all_ids.each_slice(PIPELINE_BATCH) do |batch|
          customers = Onetime::Customer.load_multi(batch)
          customers.each do |cust|
            next unless cust
            next if cust.anonymous?
            next unless cust.email.to_s.match?(/\A[^@\s]+@[^@\s]+\z/)

            last_login = cust.last_login.to_f
            updated    = cust.updated.to_f
            activity   = [last_login, updated].select { |t| t > 0 }.max

            if activity && activity > 0
              cache_redis.zadd(ACTIVITY_CACHE, activity, cust.objid)
              count += 1
            else
              skipped += 1
            end

            created = cust.created.to_f
            cache_redis.zadd(CREATED_CACHE, created, cust.objid) if created > 0
          end

          print "\r  #{count + skipped}/#{total} processed..."
        end

        print "\r" + (' ' * 60) + "\r"
        [count, skipped]
      end

      def parse_duration(str)
        match = str.match(/^(\d+)(m|y)$/i)
        unless match
          raise ArgumentError, "Invalid duration '#{str}'. Use format like: 6m, 1y, 2y, 3y, 5y"
        end

        num  = match[1].to_i
        unit = match[2].downcase

        case unit
        when 'm' then num * SECONDS_IN_MONTH
        when 'y' then num * SECONDS_IN_YEAR
        end
      end

      # parse_ts, parse_json_field, redis_client_from_url, redact_url,
      # format_ttl, ensure_cache, finalize_cache, and time/batch constants
      # are provided by Customers::Shared

      # Load customer record from source. When using --redis-url, reads
      # raw fields via HMGET (no model loading). Otherwise loads via Familia.
      def load_customer_record(source_redis, objid)
        if @using_remote
          load_customer_record_raw(source_redis, objid)
        else
          load_customer_record_model(objid)
        end
      end

      def load_customer_record_raw(redis, objid)
        fields     = %w[last_login updated email stripe_customer_id stripe_subscription_id]
        vals       = redis.hmget("customer:#{objid}:object", *fields)
        return nil if vals[2].nil?

        email       = parse_json_field(vals[2])
        last_login  = parse_ts(vals[0])
        updated     = parse_ts(vals[1])
        has_billing = !parse_json_field(vals[3]).to_s.empty? ||
                      !parse_json_field(vals[4]).to_s.empty?

        source, activity = activity_source(last_login, updated)
        build_record(OT::Utils.obscure_email(email.to_s), source, activity, has_billing)
      end

      def load_customer_record_model(objid)
        cust = Onetime::Customer.load(objid)
        return nil unless cust
        return nil if cust.anonymous?

        source, activity = activity_source(cust.last_login.to_f, cust.updated.to_f)
        build_record(cust.obscure_email, source, activity, stripe_billing?(cust))
      end

      def activity_source(last_login, updated)
        last_login > 0 ? ['last_login', last_login] : ['updated', updated]
      end

      def build_record(email, source, activity, billing)
        date = activity > 0 ? Time.at(activity).strftime('%Y-%m-%d') : 'unknown'
        { email: email, source: source, date: date, billing_protected: billing }
      end

      # Batch-load customer records for a slice of objids.
      # Returns a Hash of { objid => record } for records that loaded successfully.
      # In local mode, uses Familia's load_multi to fetch all records in a
      # single Redis pipeline instead of N individual HGETALL calls.
      def batch_load_customer_records(source_redis, objids)
        records = {}

        if @using_remote
          objids.each do |objid|
            record         = load_customer_record_raw(source_redis, objid)
            records[objid] = record if record
          end
        else
          models = Onetime::Customer.load_multi(objids)
          objids.zip(models).each do |objid, cust|
            next unless cust
            next if cust.anonymous?

            source, activity = activity_source(cust.last_login.to_f, cust.updated.to_f)
            record           = build_record(cust.obscure_email, source, activity, stripe_billing?(cust))
            record[:_model]  = cust
            records[objid]   = record
          end
        end

        records
      end

      # Delete customer keys directly from a remote Redis (no model, no index cleanup).
      # Used when --redis-url points at a pre-migration db where indexes will be abandoned.
      def delete_customer_keys(redis, objid)
        keys_to_del = CUSTOMER_SUB_KEYS.map { |suffix| "customer:#{objid}:#{suffix}" }
        # Also try the bare key (Familia v1 pattern)
        keys_to_del << "customer:#{objid}"

        # Only delete keys that exist
        existing = keys_to_del.select { |k| redis.exists?(k) }
        redis.del(*existing) unless existing.empty?
      end

      # Check if customer has any Stripe billing association.
      # Checks both deprecated v1 fields on Customer and current
      # Organization billing fields. If ANY association exists,
      # the customer is protected from purge.
      def stripe_billing?(cust)
        return true unless cust.stripe_customer_id.to_s.empty?
        return true unless cust.stripe_subscription_id.to_s.empty?

        orgs = cust.organization_instances.to_a
        orgs.any? do |org|
          next false unless org

          !org.stripe_customer_id.to_s.empty?
        end
      rescue StandardError => ex
        OT.le "[purge] Error checking billing for #{cust.objid}: #{ex.message}"
        true
      end
    end

    register 'customers purge', CustomersPurgeCommand
  end
end
