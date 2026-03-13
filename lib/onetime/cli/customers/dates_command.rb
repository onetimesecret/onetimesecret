# lib/onetime/cli/customers/dates_command.rb
#
# frozen_string_literal: true

# Report on customer record dates: creation year distribution or age buckets.
# Uses Redis SCAN to discover customer:*:object keys and caches timestamps
# in temporary sorted sets (30min TTL) for fast repeated queries.
#
# Usage:
#   bin/ots customers dates                    # Count by creation year
#   bin/ots customers dates --by-age           # Count by age bucket
#   bin/ots customers dates --refresh          # Force cache rebuild

module Onetime
  module CLI
    class CustomersDatesCommand < Command
      desc 'Report customer record dates and age distribution'

      CREATED_CACHE = 'tmp:cli:cust_by_created'
      ACTIVITY_CACHE = 'tmp:cli:cust_by_activity'
      FIELD_GAPS = 'tmp:cli:cust_field_gaps'
      CACHE_TTL = 1800 # 30 minutes
      SCAN_COUNT = 200

      option :by_age,
        type: :boolean,
        default: false,
        desc: 'Group by age bucket instead of creation year'

      option :refresh,
        type: :boolean,
        default: false,
        desc: 'Clear cached scan data and rebuild'

      def call(by_age: false, refresh: false, **)
        boot_application!
        redis = Familia.dbclient

        if refresh
          redis.del(CREATED_CACHE, ACTIVITY_CACHE, FIELD_GAPS)
          puts "Cache cleared."
        end

        ensure_cache(redis)

        if by_age
          show_by_age(redis)
        else
          show_by_year(redis)
        end
      end

      private

      def ensure_cache(redis)
        if redis.exists?(CREATED_CACHE)
          ttl = redis.ttl(CREATED_CACHE)
          count = redis.zcard(CREATED_CACHE)
          puts "Using cached data: #{count} records (expires in #{format_ttl(ttl)})"
          puts
          return
        end

        build_cache(redis)
      end

      def build_cache(redis)
        puts "Scanning customer:*:object keys..."

        # Phase 1: Collect keys via SCAN
        keys = []
        redis.scan_each(match: 'customer:*:object', count: SCAN_COUNT) do |key|
          keys << key
        end

        # Fallback if no :object suffix keys exist
        if keys.empty?
          puts "  No customer:*:object keys found. Using instances index..."
          count, no_date = build_cache_from_instances(redis)
          finalize_cache(redis, count, no_date)
          return
        end

        puts "  Found #{keys.size} keys. Reading timestamps..."

        # Phase 2: Pipeline HMGET in batches
        count = 0
        gaps = { 'no_created' => 0, 'no_updated' => 0, 'no_last_login' => 0, 'total' => 0 }

        keys.each_slice(500) do |batch|
          results = redis.pipelined do |pipe|
            batch.each do |key|
              pipe.hmget(key, 'created', 'updated', 'last_login', 'role', 'email')
            end
          end

          batch.zip(results).each do |key, fields|
            created_raw, updated_raw, last_login_raw, role_raw, email_raw = fields

            # Skip anonymous/system records
            role = parse_json_field(role_raw)
            next if role == 'anonymous'

            email = parse_json_field(email_raw)
            next unless email.to_s.include?('@')

            objid = key.split(':')[1]
            gaps['total'] += 1

            created = parse_ts(created_raw)
            updated = parse_ts(updated_raw)
            last_login = parse_ts(last_login_raw)

            # Track missing fields
            gaps['no_created'] += 1 if created <= 0
            gaps['no_updated'] += 1 if updated <= 0
            gaps['no_last_login'] += 1 if last_login <= 0

            if created > 0
              redis.zadd(CREATED_CACHE, created, objid)
              count += 1
            end

            # Also cache activity timestamps (used by purge command)
            activity = [last_login, updated].select { |t| t > 0 }.max
            redis.zadd(ACTIVITY_CACHE, activity, objid) if activity && activity > 0
          end
        end

        redis.mapped_hmset(FIELD_GAPS, gaps)
        redis.expire(FIELD_GAPS, CACHE_TTL)

        finalize_cache(redis, count, gaps['no_created'])
      end

      def build_cache_from_instances(redis)
        count = 0
        gaps = { 'no_created' => 0, 'no_updated' => 0, 'no_last_login' => 0, 'total' => 0 }
        all_ids = Onetime::Customer.instances.all
        total = all_ids.size

        puts "  Loading #{total} customers from instances index..."

        all_ids.each_slice(500) do |batch|
          customers = Onetime::Customer.load_multi(batch)
          customers.each do |cust|
            next unless cust
            next if cust.anonymous?
            next unless cust.email.to_s.include?('@')

            gaps['total'] += 1

            created = cust.created.to_f
            updated = cust.updated.to_f
            last_login = cust.last_login.to_f

            gaps['no_created'] += 1 if created <= 0
            gaps['no_updated'] += 1 if updated <= 0
            gaps['no_last_login'] += 1 if last_login <= 0

            if created > 0
              redis.zadd(CREATED_CACHE, created, cust.objid)
              count += 1
            end

            activity = [last_login, updated].select { |t| t > 0 }.max
            redis.zadd(ACTIVITY_CACHE, activity, cust.objid) if activity && activity > 0
          end

          print "\r  #{count + gaps['no_created']}/#{total} processed..."
        end

        print "\r" + (' ' * 60) + "\r"

        redis.mapped_hmset(FIELD_GAPS, gaps)
        redis.expire(FIELD_GAPS, CACHE_TTL)

        [count, gaps['no_created']]
      end

      def finalize_cache(redis, count, no_date)
        [CREATED_CACHE, ACTIVITY_CACHE].each do |key|
          redis.expire(key, CACHE_TTL) if redis.exists?(key)
        end

        puts "Cached #{count} records (#{no_date} skipped, no created date)"
        puts "Cache valid for 30 minutes (--refresh to rebuild)"
        puts
      end

      def show_by_year(redis)
        all = redis.zrangebyscore(CREATED_CACHE, '-inf', '+inf', with_scores: true)
        gaps = redis.hgetall(FIELD_GAPS)
        total_records = gaps['total'].to_i
        dated = all.size

        by_year = Hash.new(0)
        all.each do |_objid, score|
          year = Time.at(score).year
          by_year[year] += 1
        end

        puts "Customer records by creation year (#{total_records} total)"
        puts '-' * 30
        by_year.sort.each do |year, ct|
          puts format('  %d  %5d', year, ct)
        end

        show_field_gaps(gaps, dated)
      end

      def show_by_age(redis)
        now = Time.now.to_f
        gaps = redis.hgetall(FIELD_GAPS)
        total_records = gaps['total'].to_i
        dated = redis.zcard(CREATED_CACHE)

        # Each bracket: [label, min_age_secs, max_age_secs]
        # age = now - created_at
        age_brackets = [
          ['0-6m',    nil,                6 * 30 * 86400],
          ['6m-12m',  6 * 30 * 86400,   12 * 30 * 86400],
          ['12m-18m', 12 * 30 * 86400,  18 * 30 * 86400],
          ['18m-2y',  18 * 30 * 86400,   2 * 365 * 86400],
          ['2y-3y',    2 * 365 * 86400,  3 * 365 * 86400],
          ['3y-5y',    3 * 365 * 86400,  5 * 365 * 86400],
          ['5y+',      5 * 365 * 86400, nil],
        ]

        puts "Customer records by account age (#{total_records} total)"
        puts '-' * 30

        age_brackets.each do |label, min_age, max_age|
          # age = now - created → created = now - age
          # min_age <= age < max_age → (now - max_age) < created <= (now - min_age)
          if min_age.nil?
            # Youngest bucket: age < max_age → created > now - max_age
            score_min = "(#{now - max_age}"
            score_max = '+inf'
          elsif max_age.nil?
            # Oldest bucket: age >= min_age → created <= now - min_age
            score_min = '-inf'
            score_max = (now - min_age).to_s
          else
            # Middle bucket: min_age <= age < max_age
            score_min = "(#{now - max_age}"
            score_max = (now - min_age).to_s
          end

          ct = redis.zcount(CREATED_CACHE, score_min, score_max)
          puts format('  %-10s %5d', label, ct)
        end

        show_field_gaps(gaps, dated)
      end

      def show_field_gaps(gaps, dated)
        no_created = gaps['no_created'].to_i
        no_updated = gaps['no_updated'].to_i
        no_last_login = gaps['no_last_login'].to_i
        total = gaps['total'].to_i

        return if no_created == 0 && no_updated == 0 && no_last_login == 0

        puts
        puts "Missing date fields (of #{total} records)"
        puts '-' * 30
        puts format('  %-16s %5d', 'no created', no_created) if no_created > 0
        puts format('  %-16s %5d', 'no updated', no_updated) if no_updated > 0
        puts format('  %-16s %5d', 'no last_login', no_last_login) if no_last_login > 0
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

      def format_ttl(seconds)
        if seconds >= 60
          "#{seconds / 60}m #{seconds % 60}s"
        else
          "#{seconds}s"
        end
      end
    end

    register 'customers dates', CustomersDatesCommand
  end
end
