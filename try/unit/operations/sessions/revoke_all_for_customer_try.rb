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
# - EXACTLY ONE AdminAuditEvent (verb 'session.revoke_all') with the kill counts
# - rodauth_rows_deleted is 0 here (simple/test mode: no auth DB)
# - IDEMPOTENT: a second call returns revoked:true with zero counts
#
# Run: try --agent try/unit/operations/sessions/revoke_all_for_customer_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/revoke_all_for_customer'

RAFC  = Onetime::Operations::Sessions::RevokeAllForCustomer
Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::AdminAuditEvent
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
@tracked = ["tryall_a_#{@nonce}", "tryall_b_#{@nonce}"]
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
@untracked = "tryall_untracked_#{@nonce}"
DB.set("session:#{@untracked}", @codec.encode({ 'authenticated' => true,
                                                'external_id' => @extid, 'email' => @cust.email }))

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

## a second revoke-all still returns revoked:true, now with zero kill counts
AE.events.clear
@res2 = RAFC.new(custid: @extid, actor: @actor).call
[@res2.revoked, @res2.blobs_deleted, @res2.untracked_deleted]
#=> [true, 0, 0]

## it STILL audits — the colonel took an intentional action
AE.count
#=> 1

# Cleanup
@tracked.each { |sid| SM.load(sid)&.destroy!; DB.del("session:#{sid}") }
DB.del("session:#{@untracked}")
DB.del("session:#{@mislabeled}")
DB.del("session:#{@other_sid}")
@cust.active_sessions.clear
@cust.destroy!
@other.destroy!
AE.events.clear
