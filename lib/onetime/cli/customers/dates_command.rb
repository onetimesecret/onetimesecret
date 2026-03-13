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

      CREATED_CACHE  = 'tmp:cli:cust_by_created'
      ACTIVITY_CACHE = 'tmp:cli:cust_by_activity'
      FIELD_GAPS     = 'tmp:cli:cust_field_gaps'
      CACHE_TTL      = 1800 # 30 minutes
      SCAN_COUNT     = 200

      option :by_age,
        type: :boolean,
        default: false,
        desc: 'Group by age bucket instead of creation year'

      option :refresh,
        type: :boolean,
        default: false,
        desc: 'Clear cached scan data and rebuild'

      option :redis_url,
        type: :string,
        default: nil,
        desc: 'Redis/Valkey URL to scan (e.g., redis://host:6379/6)'

      def call(by_age: false, refresh: false, redis_url: nil, **)
        boot_application!

        # Source: where to SCAN customer keys from
        # Cache: where to store temp sorted sets (always the configured db)
        cache_redis   = Familia.dbclient
        source_redis  = redis_url ? redis_client_from_url(redis_url) : cache_redis
        @using_remote = !redis_url.nil?

        if @using_remote
          puts "Source: #{redact_url(redis_url)}"
          puts 'Cache:  configured db (temp keys)'
          puts
        end

        if refresh
          cache_redis.del(CREATED_CACHE, ACTIVITY_CACHE, FIELD_GAPS)
          puts 'Cache cleared.'
        end

        ensure_cache(source_redis, cache_redis)

        if by_age
          show_by_age(cache_redis)
        else
          show_by_year(cache_redis)
        end
      end

      private

      def ensure_cache(source_redis, cache_redis)
        if cache_redis.exists?(CREATED_CACHE)
          ttl   = cache_redis.ttl(CREATED_CACHE)
          count = cache_redis.zcard(CREATED_CACHE)
          puts "Using cached data: #{count} records (expires in #{format_ttl(ttl)})"
          puts
          return
        end

        build_cache(source_redis, cache_redis)
      end

      def build_cache(source_redis, cache_redis)
        puts 'Scanning customer:*:object keys...'

        # Phase 1: Collect keys via SCAN (from source)
        keys = []
        source_redis.scan_each(match: 'customer:*:object', count: SCAN_COUNT) do |key|
          keys << key
        end

        # Fallback to instances index (only when scanning local db)
        if keys.empty? && !@using_remote
          puts '  No customer:*:object keys found. Using instances index...'
          count, no_date = build_cache_from_instances(cache_redis)
          finalize_cache(cache_redis, count, no_date)
          return
        elsif keys.empty?
          puts '  No customer:*:object keys found in source.'
          return
        end

        puts "  Found #{keys.size} keys. Reading timestamps..."

        # Phase 2: Pipeline HMGET (read from source, write cache locally)
        count = 0
        gaps  = { 'no_created' => 0, 'no_updated' => 0, 'no_last_login' => 0, 'total' => 0 }

        keys.each_slice(500) do |batch|
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
            next unless email.to_s.include?('@')

            objid          = key.split(':')[1]
            gaps['total'] += 1

            created    = parse_ts(created_raw)
            updated    = parse_ts(updated_raw)
            last_login = parse_ts(last_login_raw)

            gaps['no_created']    += 1 if created <= 0
            gaps['no_updated']    += 1 if updated <= 0
            gaps['no_last_login'] += 1 if last_login <= 0

            if created > 0
              cache_redis.zadd(CREATED_CACHE, created, objid)
              count += 1
            end

            activity = [last_login, updated].select { |t| t > 0 }.max
            cache_redis.zadd(ACTIVITY_CACHE, activity, objid) if activity && activity > 0
          end
        end

        cache_redis.mapped_hmset(FIELD_GAPS, gaps)
        cache_redis.expire(FIELD_GAPS, CACHE_TTL)

        finalize_cache(cache_redis, count, gaps['no_created'])
      end

      def build_cache_from_instances(cache_redis)
        count   = 0
        gaps    = { 'no_created' => 0, 'no_updated' => 0, 'no_last_login' => 0, 'total' => 0 }
        all_ids = Onetime::Customer.instances.all
        total   = all_ids.size

        puts "  Loading #{total} customers from instances index..."

        all_ids.each_slice(500) do |batch|
          customers = Onetime::Customer.load_multi(batch)
          customers.each do |cust|
            next unless cust
            next if cust.anonymous?
            next unless cust.email.to_s.include?('@')

            gaps['total'] += 1

            created    = cust.created.to_f
            updated    = cust.updated.to_f
            last_login = cust.last_login.to_f

            gaps['no_created']    += 1 if created <= 0
            gaps['no_updated']    += 1 if updated <= 0
            gaps['no_last_login'] += 1 if last_login <= 0

            if created > 0
              cache_redis.zadd(CREATED_CACHE, created, cust.objid)
              count += 1
            end

            activity = [last_login, updated].select { |t| t > 0 }.max
            cache_redis.zadd(ACTIVITY_CACHE, activity, cust.objid) if activity && activity > 0
          end

          print "\r  #{count + gaps['no_created']}/#{total} processed..."
        end

        print "\r" + (' ' * 60) + "\r"

        cache_redis.mapped_hmset(FIELD_GAPS, gaps)
        cache_redis.expire(FIELD_GAPS, CACHE_TTL)

        [count, gaps['no_created']]
      end

      def finalize_cache(cache_redis, count, no_date)
        [CREATED_CACHE, ACTIVITY_CACHE].each do |key|
          cache_redis.expire(key, CACHE_TTL) if cache_redis.exists?(key)
        end

        puts "Cached #{count} records (#{no_date} skipped, no created date)"
        puts 'Cache valid for 30 minutes (--refresh to rebuild)'
        puts
      end

      def show_by_year(redis)
        all           = redis.zrangebyscore(CREATED_CACHE, '-inf', '+inf', with_scores: true)
        gaps          = redis.hgetall(FIELD_GAPS)
        total_records = gaps['total'].to_i
        dated         = all.size

        by_year = Hash.new(0)
        all.each do |_objid, score|
          year           = Time.at(score).year
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
        now           = Time.now.to_f
        gaps          = redis.hgetall(FIELD_GAPS)
        total_records = gaps['total'].to_i
        dated         = redis.zcard(CREATED_CACHE)

        # Each bracket: [label, min_age_secs, max_age_secs]
        # age = now - created_at
        age_brackets = [
          ['0-6m',    nil, 6 * 30 * 86_400],
          ['6m-12m',  6 * 30 * 86_400,   12 * 30 * 86_400],
          ['12m-18m', 12 * 30 * 86_400,  18 * 30 * 86_400],
          ['18m-2y',  18 * 30 * 86_400,   2 * 365 * 86_400],
          ['2y-3y',    2 * 365 * 86_400,  3 * 365 * 86_400],
          ['3y-5y',    3 * 365 * 86_400,  5 * 365 * 86_400],
          ['5y+',      5 * 365 * 86_400, nil],
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

      def show_field_gaps(gaps, _dated)
        no_created    = gaps['no_created'].to_i
        no_updated    = gaps['no_updated'].to_i
        no_last_login = gaps['no_last_login'].to_i
        total         = gaps['total'].to_i

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

      def redis_client_from_url(url)
        uri = URI.parse(url)
        db  = uri.path.to_s.sub('/', '').to_i

        Redis.new(
          host: uri.host,
          port: uri.port || 6379,
          db: db,
          password: uri.password,
          username: uri.user == '' ? nil : uri.user,
          timeout: 30,
          reconnect_attempts: 3,
        )
      end

      def redact_url(url)
        url.sub(/:[^:@\/]+@/, ':***@')
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
