# try/unit/operations/sessions/revoke_all_for_customer_except_current_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the self-service EXCEPT-CURRENT revoke op (security finding M-2:
# sessions must not survive a password change/reset):
#   Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent
#
# This is the Redis-only primitive the auth password hooks use. Where
# RevokeAllForCustomer clears EVERY session (incl. current) + the Rodauth SQL rows
# + writes an admin audit event, this op:
# - preserves ONE current session (the one the user is changing their password from)
# - is Redis-only (no Rodauth SQL, no AdminAuditEvent)
# - still kills untracked (pre-sidecar) blobs via the best-effort scan
#
# Covers:
# - every OTHER tracked blob is deleted; the current one SURVIVES
# - an untracked (pre-sidecar) blob for the target is swept (unless it IS current)
# - a DIFFERENT customer's session is untouched (identity match is exact)
# - the preserved sid keeps BOTH its sidecar and its index entry; revoked sids lose
#   both
# - NO AdminAuditEvent is written (self-service, not an admin action)
# - except_session_id: nil revokes ALL (parity with RevokeAllForCustomer, sans SQL/audit)
# - scan_untracked: false skips the best-effort sweep (tracked-only kill) so the
#   password hooks keep the keyspace SCAN out of Rodauth's open SQL transaction
# - honor_credential_watermark: true spares blobs authenticated STRICTLY AFTER
#   Customer#last_password_update (the async sweep must not kill the rotated
#   current session or a fresh post-reset login); a blob exactly AT the watermark
#   is a same-second pre-change session and is REVOKED (mirrors the auth-time <=
#   rejection); stale blobs and blobs with no authenticated_at stamp still die; a
#   nil watermark degrades to the unguarded revoke; flag off (default) ignores the
#   watermark entirely
#
# Run: try --agent try/unit/operations/sessions/revoke_all_for_customer_except_current_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'securerandom'
require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/revoke_all_for_customer_except_current'
# The op deliberately does NOT write admin audit events; require the model here so
# the "no AdminAuditEvent was written" assertion can reference the class.
require 'onetime/models/admin_audit_event'

RXC   = Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent
Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::AdminAuditEvent
DB    = Familia.dbclient

@nonce = Familia.generate_id[0, 12]
@codec = Onetime::SessionCodec.from_config

@cust = Onetime::Customer.create!(email: "revokexc_#{@nonce}@example.com")
@cust.verified = 'true'
@cust.save
@extid = @cust.extid

# A DIFFERENT customer whose session MUST survive (proves the sweep match is exact).
@other = Onetime::Customer.create!(email: "otherxc_#{@nonce}@example.com")
@other.verified = 'true'
@other.save

# Two TRACKED sessions via the real write path: @current is the session the user is
# changing their password FROM (must survive); @revoked is another device (must die).
# REAL 64-hex sids (#3858): the per-value sidecar purge is format-gated, and this
# file must prove revoked sids lose their sidecar keys while the PRESERVED
# current sid keeps its own.
@current = SecureRandom.hex(32)
@revoked = SecureRandom.hex(32)
[@current, @revoked].each do |sid|
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => @extid,
                    'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
  ).call
  DB.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                           'external_id' => @extid, 'email' => @cust.email }))
end

# One UNTRACKED session for the target: a real blob, no sidecar, not in the index
# (a pre-sidecar session). Only the best-effort scan can catch it.
@untracked = SecureRandom.hex(32)
DB.set("session:#{@untracked}", @codec.encode({ 'authenticated' => true,
                                                'external_id' => @extid, 'email' => @cust.email }))

# Per-value sidecar keys (#3858) for all three of the target's sids. The
# revoke must purge @revoked's and @untracked's; @current's must SURVIVE —
# killing a live session's short-TTL state would corrupt the very session the
# op promises to keep.
DB.set("sidecar:#{@current}:awaiting_mfa", 'sidecar-envelope')
DB.set("sidecar:#{@revoked}:awaiting_mfa", 'sidecar-envelope')
DB.set("sidecar:#{@untracked}:domain_context", 'sidecar-envelope')

# The other customer's blob — different identity, not tracked by @cust, left alone.
@other_sid = "tryxc_other_#{@nonce}"
DB.set("session:#{@other_sid}", @codec.encode({ 'authenticated' => true,
                                               'external_id' => @other.extid, 'email' => @other.email }))

# ---- pre-conditions ---------------------------------------------------

## before: all four target-relevant blobs exist
[
  Store.find_key(DB, @current).nil?,
  Store.find_key(DB, @revoked).nil?,
  Store.find_key(DB, @untracked).nil?,
  Store.find_key(DB, @other_sid).nil?,
]
#=> [false, false, false, false]

## the index tracks the two normal sids (not the untracked one)
@cust.active_sessions.revrange(0, -1).sort == [@current, @revoked].sort
#=> true

# ---- revoke-except-current: keep @current, kill everything else --------

## reports revoked:true and 2 blobs killed (1 other tracked + 1 untracked); NOT the current one
@ae_before = AE.count
@res = RXC.new(custid: @extid, except_session_id: @current).call
[@res.revoked, @res.blobs_deleted]
#=> [true, 2]

## exactly ONE of those kills was an untracked (pre-sidecar) blob from the sweep
@res.untracked_deleted
#=> 1

## the keyspace is small, so the untracked sweep did NOT hit its cap
@res.scan_capped
#=> false

## the CURRENT session's blob SURVIVES — the user stays logged in on this device
Store.find_key(DB, @current).nil?
#=> false

## the other tracked session and the untracked session are BOTH gone
[Store.find_key(DB, @revoked), Store.find_key(DB, @untracked)]
#=> [nil, nil]

## [#3858] the revoked sids' per-value sidecar keys died with their blobs
## (tracked kill AND untracked sweep), while the PRESERVED current session
## keeps its sidecar keys — its live state stays fully intact
[DB.exists("sidecar:#{@revoked}:awaiting_mfa", "sidecar:#{@untracked}:domain_context"),
 DB.exists("sidecar:#{@current}:awaiting_mfa")]
#=> [0, 1]

## the OTHER customer's session is untouched
Store.find_key(DB, @other_sid).nil?
#=> false

## the preserved session keeps BOTH its sidecar and its index entry
[SM.load(@current).nil?, @cust.active_sessions.revrange(0, -1)]
#=> [false, ["#{@current}"]]

## the revoked session lost its sidecar
SM.load(@revoked).nil?
#=> true

## NO admin audit event was written — this is a self-service revoke, not an admin action
AE.count == @ae_before
#=> true

# ---- except_session_id: nil revokes ALL (incl. the previously-kept current) ----

## a nil exception clears the last remaining (current) session too
@res2 = RXC.new(custid: @extid, except_session_id: nil).call
[@res2.revoked, @res2.blobs_deleted, Store.find_key(DB, @current).nil?, @cust.active_sessions.revrange(0, -1)]
#=> [true, 1, true, []]

## [#3858] once nothing spares it, the former current sid's sidecar keys are
## purged with its blob too
DB.exists("sidecar:#{@current}:awaiting_mfa")
#=> 0

# ---- scan_untracked: false skips the sweep (tracked-only kill) ---------
# The password hooks pass scan_untracked: false so the expensive keyspace SCAN
# never runs inside Rodauth's open SQL transaction. A fresh tracked + untracked
# pair proves the tracked blob still dies while the UNTRACKED one SURVIVES.
# (Setup lives in the test body so it runs in the shared binding before the op.)

## scan_untracked:false kills the tracked blob only; untracked_deleted is 0, scan not capped
@st_tracked   = "tryxc_st_tracked_#{@nonce}"
@st_untracked = "tryxc_st_untracked_#{@nonce}"
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @st_tracked,
  session_data: { 'authenticated' => true, 'external_id' => @extid,
                  'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
).call
DB.set("session:#{@st_tracked}", @codec.encode({ 'authenticated' => true,
                                                 'external_id' => @extid, 'email' => @cust.email }))
DB.set("session:#{@st_untracked}", @codec.encode({ 'authenticated' => true,
                                                   'external_id' => @extid, 'email' => @cust.email }))
@res3 = RXC.new(custid: @extid, except_session_id: nil, scan_untracked: false).call
[@res3.revoked, @res3.blobs_deleted, @res3.untracked_deleted, @res3.scan_capped]
#=> [true, 1, 0, false]

## the tracked blob is gone; the UNTRACKED blob SURVIVES (the sweep was skipped)
[Store.find_key(DB, @st_tracked).nil?, Store.find_key(DB, @st_untracked).nil?]
#=> [true, false]

# ---- honor_credential_watermark: spare post-credential-change sessions -
# The async sweep (#3810) runs SECONDS after the credential change; blobs
# authenticated STRICTLY AFTER Customer#last_password_update are legitimate
# post-change sessions (the rotated current session, a fresh post-reset login)
# and must SURVIVE. A blob authenticated exactly AT the watermark is a
# same-second pre-change session and is REVOKED (mirrors the auth-time `<=`
# rejection). Blobs without an authenticated_at stamp coerce to 0 and
# die whenever a watermark is in force (fail-secure: stale legacy blob).

## flag ON: a TRACKED fresh blob (authenticated after the watermark) is SPARED
## while a TRACKED stale one still dies
# @st_untracked (no authenticated_at) deliberately survived the previous
# section; drop it here so this section's sweeps count ONLY their own blobs.
DB.del("session:#{@st_untracked}")
@wm = Familia.now.to_i - 60
@cust.last_password_update = @wm
@cust.save
@wm_fresh = "tryxc_wm_fresh_#{@nonce}"
@wm_stale = "tryxc_wm_stale_#{@nonce}"
[@wm_fresh, @wm_stale].each do |sid|
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => @extid,
                    'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
  ).call
end
DB.set("session:#{@wm_fresh}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                               'authenticated_at' => @wm + 30 }))
DB.set("session:#{@wm_stale}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                               'authenticated_at' => @wm - 3600 }))
@res4 = RXC.new(custid: @extid, except_session_id: nil, honor_credential_watermark: true).call
[@res4.blobs_deleted, Store.find_key(DB, @wm_fresh).nil?, Store.find_key(DB, @wm_stale).nil?]
#=> [1, false, true]

## the SPARED session keeps BOTH its sidecar and its index entry (fully alive,
## exactly like the preserved current session)
[SM.load(@wm_fresh).nil?, @cust.active_sessions.revrange(0, -1)]
#=> [false, ["#{@wm_fresh}"]]

## flag ON: the sweep spares an UNTRACKED fresh blob too, while an untracked
## blob with NO authenticated_at coerces to 0 and dies (fail-secure)
@wm_ufresh   = "tryxc_wm_ufresh_#{@nonce}"
@wm_unstamp  = "tryxc_wm_unstamp_#{@nonce}"
DB.set("session:#{@wm_ufresh}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                                'authenticated_at' => @wm + 5 }))
DB.set("session:#{@wm_unstamp}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                                 'email' => @cust.email }))
@res5 = RXC.new(custid: @extid, except_session_id: nil, honor_credential_watermark: true).call
[@res5.blobs_deleted, @res5.untracked_deleted,
 Store.find_key(DB, @wm_ufresh).nil?, Store.find_key(DB, @wm_unstamp).nil?]
#=> [1, 1, false, true]

## flag ON but a nil watermark degrades to the unguarded revoke — the
## previously-spared fresh blobs (tracked @wm_fresh + untracked @wm_ufresh) die
@cust.last_password_update = nil
@cust.save
@res6 = RXC.new(custid: @extid, except_session_id: nil, honor_credential_watermark: true).call
[@res6.blobs_deleted, @res6.untracked_deleted,
 Store.find_key(DB, @wm_fresh).nil?, Store.find_key(DB, @wm_ufresh).nil?]
#=> [2, 1, true, true]

## flag OFF (default): a positive watermark is IGNORED — a fresh tracked blob
## still dies, byte-for-byte the historic behavior
@cust.last_password_update = Familia.now.to_i - 60
@cust.save
@off_fresh = "tryxc_off_fresh_#{@nonce}"
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @off_fresh,
  session_data: { 'authenticated' => true, 'external_id' => @extid,
                  'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
).call
DB.set("session:#{@off_fresh}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                                'authenticated_at' => Familia.now.to_i }))
@res7 = RXC.new(custid: @extid, except_session_id: nil).call
[@res7.blobs_deleted, Store.find_key(DB, @off_fresh).nil?]
#=> [1, true]

# ---- watermark boundary is STRICTLY AFTER: == watermark is REVOKED -----
# The auth-time check rejects authenticated_at <= watermark, so the sweep must
# match exactly: a blob authenticated AT the watermark is a same-second
# pre-change session and is REVOKED; only authenticated_at > watermark survives.
# (All prior target blobs are dead after @res7, so this section counts only its
# own two blobs.)

## a blob AT the watermark is REVOKED; a blob at watermark+1 is SPARED
@bw = Familia.now.to_i - 30
@cust.last_password_update = @bw
@cust.save
@wm_at    = "tryxc_wm_at_#{@nonce}"
@wm_after = "tryxc_wm_after_#{@nonce}"
DB.set("session:#{@wm_at}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                            'authenticated_at' => @bw }))
DB.set("session:#{@wm_after}", @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                                               'authenticated_at' => @bw + 1 }))
@res8 = RXC.new(custid: @extid, except_session_id: nil, honor_credential_watermark: true).call
[@res8.blobs_deleted, Store.find_key(DB, @wm_at).nil?, Store.find_key(DB, @wm_after).nil?]
#=> [1, true, false]

# Cleanup
[@current, @revoked, @untracked, @other_sid, @st_tracked, @st_untracked,
 @wm_fresh, @wm_stale, @wm_ufresh, @wm_unstamp, @off_fresh,
 @wm_at, @wm_after].each { |sid| SM.load(sid)&.destroy!; DB.del("session:#{sid}") }
DB.del("sidecar:#{@current}:awaiting_mfa")
DB.del("sidecar:#{@revoked}:awaiting_mfa")
DB.del("sidecar:#{@untracked}:domain_context")
@cust.active_sessions.clear
@cust.destroy!
@other.destroy!
