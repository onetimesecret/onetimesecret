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

Faster discovery alternative (if you trust onetime:customer is fully populated — it may not be on data carried over from V1):

cutoff = Time.now.to_i - (2 * 365 * 24 * 60 * 60)
old_ids = V2::Customer.values.rangebyscoreraw(0, cutoff) ; nil
old_ids.size
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
