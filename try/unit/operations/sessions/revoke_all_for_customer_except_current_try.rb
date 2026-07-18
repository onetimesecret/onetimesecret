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
#
# Run: try --agent try/unit/operations/sessions/revoke_all_for_customer_except_current_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

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
@current = "tryxc_current_#{@nonce}"
@revoked = "tryxc_revoked_#{@nonce}"
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
@untracked = "tryxc_untracked_#{@nonce}"
DB.set("session:#{@untracked}", @codec.encode({ 'authenticated' => true,
                                                'external_id' => @extid, 'email' => @cust.email }))

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

# Cleanup
[@current, @revoked, @untracked, @other_sid, @st_tracked, @st_untracked].each { |sid| SM.load(sid)&.destroy!; DB.del("session:#{sid}") }
@cust.active_sessions.clear
@cust.destroy!
@other.destroy!
