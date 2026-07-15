# try/jobs/secret_count_reconcile_job_try.rb
#
# frozen_string_literal: true

# Tests the SecretCountReconcileJob (issue #60): the off-request, bounded-SCAN
# recount that is the PRIMARY correctness mechanism for the per-customer
# secrets_active counter (which drifts UP because there is no expire/reveal
# decrement hook).
#
# Covers:
#   - reconcile recounts to the true LIVE count after simulated TTL expiry
#     (create N, expire some -> counter == remaining live count)
#   - reconcile corrects UP-drift all the way down to zero (all expired)
#   - backfill: a customer whose counter never tracked reality is seeded to
#     its true live count
#   - dry_run reports but writes nothing
#   - anonymous secrets are not tallied to any customer counter
#   - JOB_KEY / CRON constants
#
# Run: try --agent try/jobs/secret_count_reconcile_job_try.rb

require_relative '../support/test_helpers'

# Full boot (connect_to_db) — this tryout mints real secrets via
# Receipt.spawn_pair, which needs the verifiable-id HMAC secret that full boot
# configures. The maintenance-job base helpers still operate on Familia.dbclient.
OT.boot! :test

require_relative '../../lib/onetime/jobs/scheduled/maintenance/secret_count_reconcile_job'

@job   = Onetime::Jobs::Scheduled::Maintenance::SecretCountReconcileJob
@redis = Familia.dbclient
@stamp = Familia.now.to_f.to_s.gsub('.', '')

# Simulate a TTL-expired / revealed secret by deleting only its object hash key
# (exactly what Redis TTL expiry or Secret#destroy! leave behind: the key is
# gone, and no counter callback ran). The scan pattern is `secret:*:object`.
def expire_secret(secret)
  Familia.dbclient.del("secret:#{secret.objid}:object")
end

# Live count fixture: create 3 secrets, then expire 2 -> truth is 1.
@rc    = Onetime::Customer.create!(email: "rec_#{@stamp}@rec.example")
@pairs = 3.times.map { Onetime::Receipt.spawn_pair(@rc.objid, 3600, 'live') }

# Zero fixture: create 2 secrets, expire both -> truth is 0 (counter over-counts).
@zc    = Onetime::Customer.create!(email: "zero_#{@stamp}@rec.example")
@zpair = 2.times.map { Onetime::Receipt.spawn_pair(@zc.objid, 3600, 'gone') }

# Backfill fixture: 1 live secret, but the counter never tracked it (simulate a
# pre-#60 customer by forcing the counter to a wrong value).
@bf = Onetime::Customer.create!(email: "back_#{@stamp}@rec.example")
Onetime::Receipt.spawn_pair(@bf.objid, 3600, 'seed')

# Dry-run fixture: 2 live, 1 expired -> truth 1, but dry-run must not write.
@dr    = Onetime::Customer.create!(email: "dry_#{@stamp}@rec.example")
@dpair = 2.times.map { Onetime::Receipt.spawn_pair(@dr.objid, 3600, 'dry') }

# TRYOUTS

## JOB_KEY is secret_count_reconcile
@job::JOB_KEY
#=> 'secret_count_reconcile'

## CRON is a fixed daily schedule
@job::CRON
#=> '30 4 * * *'

## the increment chokepoint left the recount fixture counter at 3 before expiry
@rc.secrets_active.to_i
#=> 3

## after expiring 2 of 3, reconcile SETs the counter to the true live count (1)
@pairs[0..1].each { |(_r, s)| expire_secret(s) }
@job.reconcile
@rc.secrets_active.to_i
#=> 1

## reconcile corrects an over-counted counter all the way down to zero
@zpair.each { |(_r, s)| expire_secret(s) }
@job.reconcile
@zc.secrets_active.to_i
#=> 0

## backfill: a counter that never tracked reality is seeded to the live count
@bf.secrets_active.reset(0) # pretend the counter predates #60 (never incremented)
@job.reconcile
@bf.secrets_active.to_i
#=> 1

## dry_run reports a correction is needed but does NOT write it
expire_secret(@dpair[0][1]) # 2 live -> 1 live; counter still reads 2
@dry_report = @job.reconcile(dry_run: true)
[@dry_report[:dry_run], @dr.secrets_active.to_i]
#=> [true, 2]

## a real (non-dry) run then corrects the dry-run fixture to its live count
@job.reconcile
@dr.secrets_active.to_i
#=> 1

## anonymous secrets are never tallied to a customer counter
Onetime::Receipt.spawn_pair('anon', 3600, 'anon live')
@job.reconcile
Onetime::Customer.new(objid: 'anon').secrets_active.to_i
#=> 0

## the report exposes the expected shape
@report = @job.reconcile
[@report.key?(:secrets_scanned), @report.key?(:customers_processed),
 @report.key?(:customers_corrected), @report[:dry_run]]
#=> [true, true, true, false]

# TEARDOWN

[@rc, @zc, @bf, @dr].each { |c| c.destroy! rescue nil }
[@pairs, @zpair, @dpair].flatten(1).each { |(r, s)| r.destroy! rescue nil; s.destroy! rescue nil }
