# try/unit/operations/sessions/revoke_all_for_customer_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the sidecar REVOKE-ALL op (spec docs/specs/colonel-ui/40-*):
#   Onetime::Operations::Sessions::RevokeAllForCustomer
#
# The offboarding / takeover primitive. Where RevokeForCustomer kills ONE known
# sid from the sidecar index, this must guarantee a TOTAL lockout — so it takes
# the break-glass license the global console does and SCANs the keyspace, killing
# every blob whose identity matches the customer, INCLUDING pre-sidecar sessions
# the index never tracked. This is the load-bearing behaviour, so it is proved
# with a real untracked blob. Covers:
# - all of the target's live blobs are deleted (tracked AND untracked)
# - a DIFFERENT customer's session is untouched (identity match is exact)
# - untracked_deleted counts the blob the sidecar index did not know about
# - every sidecar destroyed + Customer#active_sessions cleared
# - EXACTLY ONE ColonelAuditEvent (verb 'session.revoke_all') with the kill counts;
#   target is the customer's EXTID however the route addressed them, falling back
#   to the raw route param only for an unresolvable customer
#   (docs/architecture/audit-logging.md "Session verbs")
# - rodauth_rows_deleted is 0 here (simple/test mode: no auth DB)
# - IDEMPOTENT: a second call returns revoked:true with zero counts
# - EXTID-INDEX DRIFT (#4205/#4217, the purge gap): a customer whose extid_lookup
#   entry is missing cannot be resolved by `custid:` (zero-count degrade), but a
#   caller holding the record passes it as `customer:` and the op kills every
#   blob WITHOUT consulting the index; exactly one of custid:/customer: is
#   required (ArgumentError otherwise)
#
# Run: try --agent try/unit/operations/sessions/revoke_all_for_customer_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'securerandom'
require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/revoke_all_for_customer'

RAFC  = Onetime::Operations::Sessions::RevokeAllForCustomer
Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::ColonelAuditEvent
DB    = Familia.dbclient

@nonce = Familia.generate_id[0, 12]
@actor = "ur1colonelpub_#{@nonce}" # a PUBLIC id (extid-shaped), never an objid
@codec = Onetime::SessionCodec.from_config

@cust = Onetime::Customer.create!(email: "revokeall_#{@nonce}@example.com")
@cust.verified = 'true'
@cust.save
@extid = @cust.extid

# A DIFFERENT customer whose session MUST survive (proves the scan match is exact).
@other = Onetime::Customer.create!(email: "other_#{@nonce}@example.com")
@other.verified = 'true'
@other.save

# Two TRACKED sessions (sidecar + index + blob), via the real write path.
# REAL 64-hex sids (#3858): the per-value sidecar purge is format-gated to
# real sids, and this file must prove BOTH purge paths (guaranteed tracked
# kill AND best-effort untracked sweep) run it.
@tracked = [SecureRandom.hex(32), SecureRandom.hex(32)]
@tracked.each do |sid|
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => @extid,
                    'ip_address' => '203.0.113.2', 'user_agent' => 'UA' },
  ).call
  DB.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                           'external_id' => @extid, 'email' => @cust.email }))
end

# One UNTRACKED session: a real blob for the target, but NO sidecar and NOT in
# the index (a pre-sidecar session). Only the best-effort scan can catch it.
@untracked = SecureRandom.hex(32)
DB.set("session:#{@untracked}", @codec.encode({ 'authenticated' => true,
                                                'external_id' => @extid, 'email' => @cust.email }))

# Per-value sidecar keys (#3858) next to a TRACKED blob and the UNTRACKED
# blob — the guaranteed kill and the best-effort sweep must each purge their
# sid's keys.
DB.set("sidecar:#{@tracked[0]}:awaiting_mfa", 'sidecar-envelope')
DB.set("sidecar:#{@untracked}:domain_context", 'sidecar-envelope')

# CAP-PROOF regression: a blob that is IN @cust's index (tracked) but whose blob
# identity does NOT match @cust. Under a scan-first design the identity match
# would skip it AND tidy would destroy its sidecar → a live-but-invisible session
# (the prod-scale bug). The guaranteed tracked-kill must delete it by index
# membership alone, without an identity check.
@mislabeled = "tryall_mislabeled_#{@nonce}"
DB.set("session:#{@mislabeled}", @codec.encode({ 'authenticated' => true,
                                                 'external_id' => @other.extid }))
@cust.active_sessions.add(@mislabeled, 1_700_000_000)

# The other customer's blob — different identity, NOT tracked by @cust, left alone.
@other_sid = "tryall_other_#{@nonce}"
DB.set("session:#{@other_sid}", @codec.encode({ 'authenticated' => true,
                                               'external_id' => @other.extid, 'email' => @other.email }))

# EXTID-INDEX DRIFT fixture: a customer whose `extid_lookup` entry is MISSING
# while the record and its sessions are live. Seeded BEFORE the index entry is
# dropped because TrackMetadata itself resolves the owner via find_by_extid.
@drift = Onetime::Customer.create!(email: "drift_#{@nonce}@example.com")
@drift.verified = 'true'
@drift.save
@drift_extid = @drift.extid

@drift_tracked = SecureRandom.hex(32)
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @drift_tracked,
  session_data: { 'authenticated' => true, 'external_id' => @drift_extid,
                  'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
).call
DB.set("session:#{@drift_tracked}", @codec.encode({ 'authenticated' => true,
                                                    'external_id' => @drift_extid, 'email' => @drift.email }))
@drift_untracked = SecureRandom.hex(32)
DB.set("session:#{@drift_untracked}", @codec.encode({ 'authenticated' => true,
                                                      'external_id' => @drift_extid, 'email' => @drift.email }))

# The drift itself: the index no longer knows this extid.
Onetime::Customer.extid_lookup.remove_field(@drift_extid)

# ---- pre-conditions ---------------------------------------------------

## before: both tracked blobs, the untracked blob, and the other's blob all exist
[
  Store.find_key(DB, @tracked[0]).nil?,
  Store.find_key(DB, @tracked[1]).nil?,
  Store.find_key(DB, @untracked).nil?,
  Store.find_key(DB, @other_sid).nil?,
]
#=> [false, false, false, false]

## the index tracks the two normal sids plus the mislabeled one (not the untracked)
@cust.active_sessions.revrange(0, -1).sort == (@tracked + [@mislabeled]).sort
#=> true

## [#3858] the seeded per-value sidecar keys exist before the revoke
DB.exists("sidecar:#{@tracked[0]}:awaiting_mfa", "sidecar:#{@untracked}:domain_context")
#=> 2

# ---- revoke-all: guaranteed tracked kill + best-effort sweep + audit ---

## revoke-all reports revoked:true and 4 blobs killed (3 tracked incl. mislabeled + 1 untracked)
AE.events.clear
@res = RAFC.new(custid: @extid, actor: @actor).call
[@res.revoked, @res.blobs_deleted]
#=> [true, 4]

## exactly ONE of those kills was an untracked (pre-sidecar) blob from the sweep
@res.untracked_deleted
#=> 1

## the keyspace is small, so the untracked sweep did NOT hit its cap
@res.scan_capped
#=> false

## no auth DB in simple/test mode → no Rodauth rows removed
@res.rodauth_rows_deleted
#=> 0

## every one of the target's live blobs is GONE — including the MISLABELED tracked
## one, proving the tracked kill is identity-independent and cap-proof
[
  Store.find_key(DB, @tracked[0]),
  Store.find_key(DB, @tracked[1]),
  Store.find_key(DB, @mislabeled),
  Store.find_key(DB, @untracked),
]
#=> [nil, nil, nil, nil]

## the OTHER customer's (untracked, non-matching) session is untouched
Store.find_key(DB, @other_sid).nil?
#=> false

## [#3858] BOTH purge paths ran: the tracked sid's AND the untracked sid's
## per-value sidecar keys died with their blobs
DB.exists("sidecar:#{@tracked[0]}:awaiting_mfa", "sidecar:#{@untracked}:domain_context")
#=> 0

## every sidecar is destroyed and the index is cleared
[SM.load(@tracked[0]).nil?, SM.load(@tracked[1]).nil?, @cust.active_sessions.revrange(0, -1)]
#=> [true, true, []]

## EXACTLY ONE audit event: verb session.revoke_all, target the extid, actor the colonel
AE.count
#=> 1

## the event is the revoke-all verb, targeting the customer, actored by the PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["session.revoke_all", "#{@extid}", "#{@actor}"]

## the audit detail carries the kill counts + scan_capped (and no secret material)
[@ev['detail']['blobs_deleted'], @ev['detail']['untracked_deleted'], @ev['detail']['rodauth_rows_deleted'], @ev['detail']['scan_capped']]
#=> [4, 1, 0, false]

# ---- idempotent second revoke-all -------------------------------------

## a second revoke-all still returns revoked:true, now with zero kill counts —
## routed by EMAIL this time, to prove the audit target normalizes to the extid
AE.events.clear
@res2 = RAFC.new(custid: @cust.email, actor: @actor).call
[@res2.revoked, @res2.blobs_deleted, @res2.untracked_deleted]
#=> [true, 0, 0]

## it STILL audits — the colonel took an intentional action — and the target is
## the customer's resolved extid, not the email the route used
[AE.count, AE.recent(1).first['target']]
#=> [1, "#{@extid}"]

# ---- unresolvable customer: audit falls back to the route param ---------

## a custid that resolves to NO customer still completes (zero counts) and audits
AE.events.clear
@ghost = "ghost_#{@nonce}@example.com"
RAFC.new(custid: @ghost, actor: @actor).call.revoked
#=> true

## with no customer to resolve, the target is the route param as given —
## nothing better exists to record
[AE.count, AE.recent(1).first['target']]
#=> [1, "#{@ghost}"]

# ---- extid-index drift: `customer:` must not depend on the index ---------

## the drift is REAL: by extid (and by objid-load of the extid) the customer
## resolves to nothing, yet the record and BOTH of its session blobs are live
[
  Onetime::Customer.load_by_extid_or_email(@drift_extid).nil?,
  Onetime::Customer.load(@drift_extid).nil?,
  @drift.exists?,
  Store.find_key(DB, @drift_tracked).nil?,
  Store.find_key(DB, @drift_untracked).nil?,
]
#=> [true, true, true, false, false]

## addressed by `custid:` (the pre-fix Purge shape) the revoke DEGRADES: zero
## counts and both blobs survive, while the trail still reads like a normal
## revoke (target is the extid either way). This is the gap; it is pinned here
## so the `customer:` block below is proven non-vacuous.
AE.events.clear
@res_by_id = RAFC.new(custid: @drift_extid, actor: @actor).call
[
  @res_by_id.blobs_deleted,
  AE.recent(1).first['target'],
  Store.find_key(DB, @drift_tracked).nil?,
  Store.find_key(DB, @drift_untracked).nil?,
]
#=> [0, "#{@drift_extid}", false, false]

## handed the record as `customer:`, the same revoke kills BOTH blobs
## (1 tracked + 1 untracked) without ever consulting the index
AE.events.clear
@res_drift = RAFC.new(customer: @drift, actor: @actor).call
[@res_drift.revoked, @res_drift.blobs_deleted, @res_drift.untracked_deleted]
#=> [true, 2, 1]

## both blobs are gone, the sidecar is destroyed and the index cleared
[
  Store.find_key(DB, @drift_tracked),
  Store.find_key(DB, @drift_untracked),
  SM.load(@drift_tracked).nil?,
  @drift.active_sessions.revrange(0, -1),
]
#=> [nil, nil, true, []]

## exactly ONE session.revoke_all event, target the record's extid, detail
## carrying blobs_deleted > 0
@drift_ev = AE.recent(1).first
[AE.count, @drift_ev['verb'], @drift_ev['target'], @drift_ev['detail']['blobs_deleted'] > 0]
#=> [1, "session.revoke_all", "#{@drift_extid}", true]

## the op used the record AS GIVEN: the index was not repopulated as a side effect
Onetime::Customer.load_by_extid_or_email(@drift_extid).nil?
#=> true

## neither kwarg is rejected: exactly one of custid:/customer: is required
begin
  RAFC.new(actor: @actor)
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## both kwargs is rejected too (no silent precedence between the two)
begin
  RAFC.new(custid: @drift_extid, customer: @drift, actor: @actor)
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

# Cleanup
@tracked.each { |sid| SM.load(sid)&.destroy!; DB.del("session:#{sid}") }
SM.load(@drift_tracked)&.destroy!
DB.del("session:#{@drift_tracked}")
DB.del("session:#{@drift_untracked}")
@drift.active_sessions.clear
@drift.destroy!
DB.del("session:#{@untracked}")
DB.del("session:#{@mislabeled}")
DB.del("session:#{@other_sid}")
DB.del("sidecar:#{@tracked[0]}:awaiting_mfa")
DB.del("sidecar:#{@untracked}:domain_context")
@cust.active_sessions.clear
@cust.destroy!
@other.destroy!
AE.events.clear
