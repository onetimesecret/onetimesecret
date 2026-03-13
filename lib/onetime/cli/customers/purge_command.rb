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
    class CustomersPurgeCommand < Command
      desc 'Purge inactive customer records by last activity date'

      ACTIVITY_CACHE = 'tmp:cli:cust_by_activity'
      CREATED_CACHE = 'tmp:cli:cust_by_created'
      CACHE_TTL = 1800 # 30 minutes
      SCAN_COUNT = 200
      BATCH_SIZE = 50

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

      def call(older_than: nil, purge: false, refresh: false, **)
        unless older_than
          show_usage
          return
        end

        boot_application!
        redis = Familia.dbclient

        threshold_secs = parse_duration(older_than)
        cutoff = Time.now - threshold_secs
        cutoff_epoch = cutoff.to_f

        if refresh
          redis.del(ACTIVITY_CACHE, CREATED_CACHE)
          puts "Cache cleared."
        end

        ensure_cache(redis)

        # Get candidates: all objids with last activity before cutoff
        candidates = redis.zrangebyscore(ACTIVITY_CACHE, '-inf', cutoff_epoch.to_s)

        puts "Purge candidates: #{candidates.size} customers inactive since #{cutoff.strftime('%Y-%m-%d')}"
        puts "Activity source: last_login (preferred) or updated (fallback)"
        puts

        if candidates.empty?
          puts "No customers match the criteria."
          return
        end

        if purge
          execute_purge(redis, candidates, cutoff)
        else
          show_dry_run(redis, candidates, older_than)
        end
      end

      private

      def show_usage
        puts <<~USAGE
          Customer Purge Tool

          Usage:
            bin/ots customers purge --older-than DURATION [options]

          Duration format:
            6m, 12m, 18m    Months (30-day months)
            1y, 2y, 3y, 5y  Years (365-day years)

          Options:
            --older-than DURATION   Activity age threshold (required)
            --purge                 Execute deletion (default is dry-run)
            --refresh               Force cache rebuild before selecting

          Examples:
            bin/ots customers purge --older-than 3y              # Preview
            bin/ots customers purge --older-than 3y --purge      # Execute
            bin/ots customers purge --older-than 5y --refresh    # Rescan + preview

          The dry-run caches candidates for 30 minutes. Running --purge
          within that window reuses the same candidate set, so you review
          exactly what will be deleted.

        USAGE
      end

      def show_dry_run(redis, candidates, duration)
        puts "DRY RUN - No records will be modified"
        puts

        # Iterate all candidates (same code path as purge, minus destroy!)
        purgeable_count = 0
        billing_protected = 0
        no_load = 0
        shown = 0

        candidates.each do |objid|
          cust = Onetime::Customer.load(objid)
          unless cust
            no_load += 1
            next
          end

          if has_stripe_billing?(cust)
            billing_protected += 1
            next
          end

          last_login = cust.last_login.to_f
          updated = cust.updated.to_f

          if last_login > 0
            source = 'last_login'
            activity = last_login
          else
            source = 'updated'
            activity = updated
          end

          date = activity > 0 ? Time.at(activity).strftime('%Y-%m-%d') : 'unknown'
          purgeable_count += 1

          # Show first 20 in detail, then just count
          if shown < 20
            puts format("  %-36s %s=%-10s %s", objid, source, date, cust.obscure_email)
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
        puts "BEFORE PURGING:"
        puts "  1. Back up Redis: redis-cli BGSAVE"
        puts "  2. Export affected emails if needed for notification"
        puts "  3. Run during off-peak hours for large sets (#{purgeable_count} records)"
        puts "  4. Each destroy! removes: object hash, indexes, metadata, relationships"
        puts "  5. This action is NOT reversible without a Redis backup"
        puts
        puts "NOTE: If running in full auth mode, corresponding SQL accounts"
        puts "  in the auth database are NOT removed by this command. Clean"
        puts "  up orphaned accounts separately if needed."
        puts
        puts "To execute:"
        puts "  bin/ots customers purge --older-than #{duration} --purge"
      end

      def execute_purge(redis, candidates, cutoff)
        total = candidates.size
        destroyed = 0
        skipped = 0
        billing_protected = 0
        errors = []

        puts "PURGING #{total} candidates inactive since #{cutoff.strftime('%Y-%m-%d')}..."
        puts "(Customers with Stripe billing will be skipped automatically)"
        puts

        candidates.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
          batch.each do |objid|
            cust = Onetime::Customer.load(objid)
            unless cust
              skipped += 1
              next
            end

            if cust.anonymous?
              skipped += 1
              next
            end

            if has_stripe_billing?(cust)
              billing_protected += 1
              OT.info "[purge] Protected (billing): #{objid} #{cust.obscure_email}"
              next
            end

            begin
              email_obscured = cust.obscure_email
              cust.destroy!

              # Clean up cache entries
              redis.zrem(ACTIVITY_CACHE, objid)
              redis.zrem(CREATED_CACHE, objid)

              destroyed += 1
              OT.info "[purge] Destroyed #{objid} #{email_obscured}"
            rescue => ex
              errors << "#{objid}: #{ex.message}"
              OT.le "[purge] Error destroying #{objid}: #{ex.message}"
            end
          end

          processed = (batch_idx + 1) * BATCH_SIZE
          processed = [processed, total].min
          print "\r  Progress: #{processed}/#{total} (#{destroyed} destroyed, #{billing_protected} billing-protected, #{skipped} skipped)"
        end

        print "\r" + (' ' * 80) + "\r"
        puts
        puts "Purge complete"
        puts '-' * 30
        puts "  Destroyed:         #{destroyed}"
        puts "  Billing-protected: #{billing_protected}"
        puts "  Skipped:           #{skipped}"
        puts "  Errors:            #{errors.size}"

        if errors.any?
          puts
          puts "  Error details:"
          errors.first(20).each { |e| puts "    #{e}" }
          puts "    ... and #{errors.size - 20} more" if errors.size > 20
        end
      end

      def ensure_cache(redis)
        if redis.exists?(ACTIVITY_CACHE)
          ttl = redis.ttl(ACTIVITY_CACHE)
          count = redis.zcard(ACTIVITY_CACHE)
          puts "Using cached data: #{count} records (expires in #{format_ttl(ttl)})"
          return
        end

        build_cache(redis)
      end

      def build_cache(redis)
        puts "Scanning customer records for activity dates..."

        # Phase 1: Collect keys via SCAN
        keys = []
        redis.scan_each(match: 'customer:*:object', count: SCAN_COUNT) do |key|
          keys << key
        end

        # Fallback if no :object suffix keys exist
        if keys.empty?
          puts "  No customer:*:object keys found. Using instances index..."
          count, skipped = build_cache_from_instances(redis)
          finalize_cache(redis, count, skipped)
          return
        end

        puts "  Found #{keys.size} keys. Reading timestamps..."

        # Phase 2: Pipeline HMGET in batches
        count = 0
        skipped = 0

        keys.each_slice(500) do |batch|
          results = redis.pipelined do |pipe|
            batch.each do |key|
              pipe.hmget(key, 'created', 'updated', 'last_login', 'role', 'email')
            end
          end

          batch.zip(results).each do |key, fields|
            created_raw, updated_raw, last_login_raw, role_raw, email_raw = fields

            role = parse_json_field(role_raw)
            next if role == 'anonymous'

            email = parse_json_field(email_raw)
            next unless email.to_s.include?('@')

            objid = key.split(':')[1]

            last_login = parse_ts(last_login_raw)
            updated = parse_ts(updated_raw)
            activity = [last_login, updated].select { |t| t > 0 }.max

            if activity && activity > 0
              redis.zadd(ACTIVITY_CACHE, activity, objid)
              count += 1
            else
              skipped += 1
            end

            # Also cache created timestamps (used by dates command)
            created = parse_ts(created_raw)
            redis.zadd(CREATED_CACHE, created, objid) if created > 0
          end
        end

        finalize_cache(redis, count, skipped)
      end

      def build_cache_from_instances(redis)
        count = 0
        skipped = 0
        all_ids = Onetime::Customer.instances.all
        total = all_ids.size

        puts "  Loading #{total} customers from instances index..."

        all_ids.each_slice(500) do |batch|
          customers = Onetime::Customer.load_multi(batch)
          customers.each do |cust|
            next unless cust
            next if cust.anonymous?
            next unless cust.email.to_s.include?('@')

            last_login = cust.last_login.to_f
            updated = cust.updated.to_f
            activity = [last_login, updated].select { |t| t > 0 }.max

            if activity && activity > 0
              redis.zadd(ACTIVITY_CACHE, activity, cust.objid)
              count += 1
            else
              skipped += 1
            end

            created = cust.created.to_f
            redis.zadd(CREATED_CACHE, created, cust.objid) if created > 0
          end

          print "\r  #{count + skipped}/#{total} processed..."
        end

        print "\r" + (' ' * 60) + "\r"
        [count, skipped]
      end

      def finalize_cache(redis, count, skipped)
        [ACTIVITY_CACHE, CREATED_CACHE].each do |key|
          redis.expire(key, CACHE_TTL) if redis.exists?(key)
        end

        puts "Cached #{count} records (#{skipped} without activity date)"
        puts "Cache valid for 30 minutes (--refresh to rebuild)"
        puts
      end

      def parse_duration(str)
        match = str.match(/^(\d+)(m|y)$/i)
        unless match
          puts "Error: Invalid duration '#{str}'. Use format like: 6m, 1y, 2y, 3y, 5y"
          exit 1
        end

        num = match[1].to_i
        unit = match[2].downcase

        case unit
        when 'm' then num * 30 * 86400
        when 'y' then num * 365 * 86400
        end
      end

      def parse_ts(raw)
        return 0.0 if raw.nil? || raw.to_s.strip.empty?
        JSON.parse(raw).to_f
      rescue JSON::ParserError
        raw.to_f
      end

      def parse_json_field(raw)
        return nil if raw.nil? || raw.to_s.strip.empty?
        JSON.parse(raw)
      rescue JSON::ParserError
        raw.to_s
      end

      # Check if customer has any Stripe billing association.
      # Checks both deprecated v1 fields on Customer and current
      # Organization billing fields. If ANY association exists,
      # the customer is protected from purge.
      def has_stripe_billing?(cust)
        # Check deprecated v1 billing fields on customer record
        return true unless cust.stripe_customer_id.to_s.empty?
        return true unless cust.stripe_subscription_id.to_s.empty?

        # Check organization billing (current architecture)
        orgs = cust.organization_instances.to_a
        orgs.any? do |org|
          next false unless org
          !org.stripe_customer_id.to_s.empty?
        end
      rescue => ex
        # If we can't determine billing status, protect the customer
        OT.le "[purge] Error checking billing for #{cust.objid}: #{ex.message}"
        true
      end

      def format_ttl(seconds)
        if seconds >= 60
          "#{seconds / 60}m #{seconds % 60}s"
        else
          "#{seconds}s"
        end
      end
    end

    register 'customers purge', CustomersPurgeCommand
  end
end
