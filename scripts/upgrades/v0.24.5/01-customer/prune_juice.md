# migrate/prune_juice.md
---

Why a custom delete path (not cust.destroy!): Familia 1.1.0.pre.rc1's default Horreum#destroy! only deletes the main
customer:CUSTID:object hash — it orphans the per-instance relation keys. CustomDomain in this codebase already worked around it; we
do the same here for Customer.

Per-customer keys deleted (5 total):
- customer:CUSTID:object — main hash
- customer:CUSTID:custom_domain — sorted set (note singular, due to suffix: override)
- customer:CUSTID:metadata — sorted set
- customer:CUSTID:feature_flags — hash
- customer:CUSTID:reset_secret — string

Plus ZREM onetime:customer CUSTID. We don't touch onetime:customers:domain (keyed by domain, not custid — separate sweep if needed).

Safety:
- Default is dry-run; delete! requires confirm: 'YES_DELETE'
- Protected: custid in [anon, GLOBAL], role in [colonel], optionally stripe_customer_id non-empty
- custid read from hash field (not key parsing) — handles legacy custids with :
- Uses UNLINK (async, non-blocking) inside pipelined blocks
- archive(custids) saves the candidate list to a timestamped Redis list before any deletes

IRB-pasteable flow:

load './migrate/prune_old_customers.rb'
PruneCust.help

# 1. Discovery — returns small summary, NOT the records
snap = PruneCust.scan(older_than: 2 * 365 * 24 * 60 * 60)
snap[:counts]
snap[:sample]

# 2. Spot-check what would be deleted
PruneCust.keys_for(snap[:custids].first)
PruneCust.sample(snap[:custids].first)

# 3. Archive list before destruction
archive_key = PruneCust.archive(snap[:custids])

# 4. Dry run (no confirm token)
PruneCust.delete!(snap[:custids])

# 5. Actually delete
PruneCust.delete!(snap[:custids], confirm: 'YES_DELETE')

# Single-record spot fix
PruneCust.delete_one!('legacy@example.com', confirm: 'YES_DELETE')

Last-activity discovery (V2::Customer.values is scored by *creation* time only, so it
can't tell us which old accounts logged in recently — we have to read the hashes).
SCAN + pipelined HMGET on just the fields we need is ~10x faster than per-key HGETALL
since Redis round-trips collapse to one per batch:

cutoff = Time.now.to_i - (5 * 365 * 24 * 60 * 60)
redis_client = V2::Customer.redis
prefix = V2::Customer.prefix
scan_pattern = "#{prefix}:*:object"
fields = %w[custid role stripe_customer_id created updated last_login]

cursor = "0"
old_ids = []
counts = Hash.new(0)
loop do
  cursor, keys = redis_client.scan(cursor, match: scan_pattern, count: 5_000)
  counts[:scanned] += keys.size
  unless keys.empty?
    rows = redis_client.pipelined { |pipe| keys.each { |k| pipe.hmget(k, *fields) } }
    keys.zip(rows).each do |_key, row|
      custid, role, stripe_id, created_s, updated_s, last_login_s = row
      if custid.to_s.empty?         then counts[:no_custid]     += 1 ; next ; end
      if %w[anon GLOBAL].include?(custid) || role == 'colonel'
                                         counts[:protected]      += 1 ; next
      end
      unless stripe_id.to_s.empty? then counts[:has_stripe]    += 1 ; next ; end
      last_active = [created_s.to_i, updated_s.to_i, last_login_s.to_i].max
      if last_active.zero?         then counts[:no_timestamps] += 1 ; next ; end
      if last_active >= cutoff     then counts[:active]        += 1 ; next ; end
      old_ids << custid
    end
  end
  break if cursor == "0"
end ; nil

old_ids.size
counts   # => {scanned:, no_custid:, protected:, has_stripe:, no_timestamps:, active:}

# Dump each candidate's :object hash to a JSONL file before pruning.
# Writes to /app/data so the artifact survives container restarts.
# Pipelined HGETALL — fast even for tens of thousands of ids.
require 'json'
require 'fileutils'
FileUtils.mkdir_p('/app/data')
path = "/app/data/old_customers_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.jsonl"
redis_client = V2::Customer.redis
prefix = V2::Customer.prefix
written = 0 ; missing = 0
File.open(path, 'w') do |f|
  old_ids.each_slice(500) do |slice|
    hashes = redis_client.pipelined { |pipe| slice.each { |id| pipe.hgetall("#{prefix}:#{id}:object") } }
    slice.zip(hashes).each do |id, h|
      if h.nil? || h.empty?
        missing += 1
        next
      end
      f.puts(JSON.generate(custid: id, object: h))
      written += 1
    end
  end
end ; nil
puts "wrote #{written} records (missing=#{missing}) → #{path}"


^readonly to report on the data.
---

Below here to modify the data.

PruneCust.delete!(old_ids, confirm: 'YES_DELETE')

The SCAN-based PruneCust.scan is slower but defensive — checks role/stripe/timestamps and works even on records missing from the
index sorted set.

❯ How to convert cutoff back to date

⏺ cutoff = Time.now.to_i - (2 * 365 * 24 * 60 * 60)
Time.at(cutoff).utc           # => 2024-04-28 ... UTC
Time.at(cutoff).utc.iso8601   # => "2024-04-28T..."
Time.at(cutoff).utc.strftime('%Y-%m-%d')

For a record's stored epoch:
h = PruneCust.sample('foo@example.com')
Time.at(h['created'].to_i).utc
Time.at(h['updated'].to_i).utc
