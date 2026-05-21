# migrate/prune_juice.rb
#
# One-off prune of stale V2::Customer records from production Redis.
#
# This is for a private build off v0.22.1; not meant for develop/main.
#
# Branch: retro/gamer
#
# ─── BACKGROUND ──────────────────────────────────────────────────
#
# Each Customer is stored as `customer:<custid>:object` (Redis hash).
# Familia 1.1.0.pre.rc1's default `Horreum#destroy!` deletes only that
# main hash and orphans the per-instance relations:
#
#   customer:<custid>:custom_domain  (sorted set; suffix override)
#   customer:<custid>:metadata       (sorted set)
#   customer:<custid>:feature_flags  (hash)
#   customer:<custid>:reset_secret   (string, 24h ttl)
#
# Plus class-level membership in `onetime:customer` (sorted set,
# scored by epoch creation time). The reverse-lookup hash
# `onetime:customers:domain` is keyed by domain (not custid) so we
# don't try to clean it from this script — handle separately if needed.
#
# ─── USAGE ───────────────────────────────────────────────────────
#
#   $ bin/ots console
#   onetime> load './migrate/prune_old_customers.rb'
#   onetime> PruneCust.help
#
# Typical flow:
#
#   # 1. Dry run discovery (loads candidates into a snapshot list)
#   onetime> snap = PruneCust.scan(older_than: 2 * 365 * 24 * 60 * 60)
#
#   # 2. Inspect the bucket counts
#   onetime> snap[:counts]
#
#   # 3. Look at a few samples by custid only (no record dump)
#   onetime> snap[:custids].first(10)
#
#   # 4. Archive the list into a Redis list for safety before any delete
#   onetime> PruneCust.archive(snap[:custids])
#
#   # 5. Real delete in batches. Hard guard: confirm token must match.
#   onetime> PruneCust.delete!(snap[:custids], confirm: 'YES_DELETE')
#
# IRB-friendly: every batch loop ends with `; nil`. Methods that touch
# many records print progress and return summary hashes (small),
# never raw record arrays.

module PruneCust
  module_function

  # ─── CONFIG ────────────────────────────────────────────────────

  SCAN_PATTERN     = "#{V2::Customer.prefix}:*:object".freeze   # customer:*:object
  SCAN_BATCH       = 5_000
  DELETE_BATCH     = 500
  PROGRESS_EVERY   = 25_000
  PROTECTED_CUSTIDS = %w[anon GLOBAL].freeze
  PROTECTED_ROLES   = %w[colonel].freeze

  # Two years in seconds, as a default cutoff. Override per call.
  DEFAULT_AGE_SECONDS = 2 * 365 * 24 * 60 * 60

  # ─── HELP ──────────────────────────────────────────────────────

  def help
    puts <<~HELP
      PruneCust — old customer pruner

        scan(older_than: SECONDS, skip_with_stripe: true)
            SCAN customer:*:object, classify by age + role.
            Returns { custids:, counts:, sample: }.

        sample(custid)
            HGETALL the raw customer hash. No object instantiation.

        keys_for(custid)
            Returns the exact Redis keys we'd delete for this custid.
            Useful for spot-checking before delete!.

        archive(custids, label: ...)
            RPUSH the candidate list into a backup Redis list under
            DB 0 with a timestamped key. Always do this before delete!.

        delete!(custids, confirm: 'YES_DELETE', batch_size: 500)
            For each custid: pipelined UNLINK of all relation keys,
            ZREM from onetime:customer.

        delete_one!(custid, confirm: 'YES_DELETE')
            Single-record version, useful for spot fixes.

      Defaults: dry_run unless confirm token is exactly 'YES_DELETE'.
      Protected: anon, GLOBAL, role=colonel are always skipped.
    HELP
    nil
  end

  # ─── DISCOVERY ─────────────────────────────────────────────────

  # @param older_than [Integer] seconds; record is "old" if BOTH
  #   created and updated epochs are older than (now - older_than).
  #   updated may be empty/zero — we treat empty as "older than dirt"
  #   and rely on created as the floor.
  # @param skip_with_stripe [Boolean] keep records where
  #   stripe_customer_id is non-empty (paid or once-paid).
  #
  # @return [Hash] { custids: [..], counts: {..}, sample: [..] }
  def scan(older_than: DEFAULT_AGE_SECONDS, skip_with_stripe: true)
    redis_client = V2::Customer.redis
    cutoff_epoch = Time.now.to_i - older_than.to_i

    cursor   = "0"
    counts   = Hash.new(0)
    candidates = []
    sample   = []

    puts "scan: pattern=#{SCAN_PATTERN} cutoff=#{Time.at(cutoff_epoch).utc.iso8601} (older_than=#{older_than}s)"
    puts "      skip_with_stripe=#{skip_with_stripe} protected=#{PROTECTED_CUSTIDS.inspect} roles=#{PROTECTED_ROLES.inspect}"

    loop do
      cursor, keys = redis_client.scan(cursor, match: SCAN_PATTERN, count: SCAN_BATCH)
      counts[:scanned] += keys.size

      keys.each do |key|
        h = redis_client.hgetall(key)
        if h.nil? || h.empty?
          counts[:empty_hash] += 1
          next
        end

        # Trust the stored custid field, not the key split — custids
        # may contain `:` (e.g. some legacy emails), and the 1381 audit
        # script established this same guard.
        custid = h['custid'].to_s
        if custid.empty?
          counts[:no_custid_field] += 1
          next
        end

        if PROTECTED_CUSTIDS.include?(custid)
          counts[:protected_custid] += 1
          next
        end

        role = h['role'].to_s
        if PROTECTED_ROLES.include?(role)
          counts[:protected_role] += 1
          next
        end

        if skip_with_stripe && !h['stripe_customer_id'].to_s.empty?
          counts[:skipped_stripe] += 1
          next
        end

        created = h['created'].to_i
        updated = h['updated'].to_i
        # last_active = max(created, updated, last_login). updated/last_login
        # can be empty strings → to_i == 0, so created acts as the floor.
        last_active = [created, updated, h['last_login'].to_i].max

        if last_active.zero?
          counts[:no_timestamps] += 1
          next
        end

        if last_active >= cutoff_epoch
          counts[:still_active] += 1
          next
        end

        counts[:candidate] += 1
        counts["candidate_role_#{role}".to_sym] += 1
        candidates << custid
        sample << { custid: custid, role: role, created: created, updated: updated } if sample.size < 10
      end

      if counts[:scanned] % PROGRESS_EVERY < SCAN_BATCH
        puts "  scanned=#{counts[:scanned]} candidates=#{counts[:candidate]}"
      end

      break if cursor == "0"
    end

    puts "scan complete: #{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    { custids: candidates, counts: counts, sample: sample }
  end

  # ─── INSPECTION ────────────────────────────────────────────────

  # Raw hash for a single customer, no object hydration.
  def sample(custid)
    redis_client = V2::Customer.redis
    redis_client.hgetall("#{V2::Customer.prefix}:#{custid}:object")
  end

  # Returns the exact set of Redis keys we'd UNLINK for this custid.
  # Uses Familia metadata, so it stays correct if relations change.
  def keys_for(custid)
    cust = V2::Customer.load(custid)
    return [] unless cust

    keys = [cust.rediskey]
    cust.class.redis_types.each_key do |relname|
      keys << cust.send(relname).rediskey
    end
    keys
  end

  # ─── ARCHIVE ───────────────────────────────────────────────────

  # Push candidate custids into a Redis list under DB 0 (Familia.redis,
  # not the customer DB) so they're separate from the data being pruned.
  # Returns the archive key.
  def archive(custids, label: 'prune_candidates')
    return if custids.nil? || custids.empty?

    key = "#{label}:#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}"
    Familia.redis.del(key)
    custids.each_slice(10_000) do |chunk|
      Familia.redis.rpush(key, chunk)
    end
    puts "archived #{custids.size} custids → #{key}"
    puts "  recover with: Familia.redis.lrange('#{key}', 0, -1)"
    key
  end

  # ─── DELETE ────────────────────────────────────────────────────

  # Returns the array of related-redis-types keys for a customer
  # without instantiating the full V2::Customer (avoids Passphrase
  # mixin et al). Mirrors what `cust.class.redis_types.keys` would
  # produce, hardcoded for this v0.22.1 schema.
  RELATION_SUFFIXES = {
    custom_domains: 'custom_domain',  # explicit suffix override in model
    metadata:       'metadata',
    feature_flags:  'feature_flags',
    reset_secret:   'reset_secret',
  }.freeze

  def static_keys_for(custid)
    base = "#{V2::Customer.prefix}:#{custid}"
    ["#{base}:object"] + RELATION_SUFFIXES.values.map { |s| "#{base}:#{s}" }
  end

  # Bulk delete. confirm token must equal 'YES_DELETE' or it dry-runs.
  #
  # Strategy per record:
  #   - UNLINK all known relation keys (async-friendly; non-blocking)
  #   - ZREM from V2::Customer.values
  # Pipelined per batch.
  #
  # Returns summary hash. Loop ends with explicit nil — no big array
  # returned to IRB.
  def delete!(custids, confirm: nil, batch_size: DELETE_BATCH)
    if custids.nil? || custids.empty?
      puts "delete!: nothing to do"
      return { deleted: 0, skipped: 0, dry_run: true }
    end

    dry_run = (confirm != 'YES_DELETE')
    puts "delete!: count=#{custids.size} dry_run=#{dry_run} batch_size=#{batch_size}"
    puts "         (pass confirm: 'YES_DELETE' to actually delete)" if dry_run

    redis_client    = V2::Customer.redis
    values_key      = V2::Customer.values.rediskey
    deleted         = 0
    skipped         = 0
    error_count     = 0
    sample_first    = nil

    custids.each_slice(batch_size).with_index do |slice, batch_idx|
      slice.each do |custid|
        if PROTECTED_CUSTIDS.include?(custid.to_s)
          skipped += 1
          next
        end
        sample_first ||= static_keys_for(custid)
      end

      if dry_run
        deleted += slice.size
      else
        begin
          redis_client.pipelined do |pipe|
            slice.each do |custid|
              next if PROTECTED_CUSTIDS.include?(custid.to_s)
              static_keys_for(custid).each { |k| pipe.unlink(k) }
              pipe.zrem(values_key, custid)
            end
          end
          deleted += slice.size
        rescue => ex
          error_count += 1
          puts "  batch #{batch_idx}: error #{ex.class}: #{ex.message}"
        end
      end

      if (batch_idx % 10).zero?
        puts "  batch=#{batch_idx} processed=#{deleted} skipped=#{skipped} errors=#{error_count}"
      end
    end ; nil

    puts "delete! done: deleted=#{deleted} skipped=#{skipped} errors=#{error_count} dry_run=#{dry_run}"
    puts "  sample keys for first non-protected custid:" if sample_first
    (sample_first || []).each { |k| puts "    #{k}" }
    { deleted: deleted, skipped: skipped, errors: error_count, dry_run: dry_run }
  end

  # Spot-fix a single custid. Same confirm gate.
  def delete_one!(custid, confirm: nil)
    delete!([custid], confirm: confirm, batch_size: 1)
  end
end

puts ""
puts "PruneCust loaded. Run PruneCust.help for usage."
puts ""
nil
