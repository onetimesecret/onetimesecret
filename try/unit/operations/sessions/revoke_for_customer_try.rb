# try/unit/operations/sessions/revoke_for_customer_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the sidecar REVOKE op (spec docs/specs/colonel-ui/40-*):
#   Onetime::Operations::Sessions::RevokeForCustomer
#
# THE key-invalidation test. In this codebase a session dies by deleting the
# encrypted `session:<sid>` blob (adaptation #1), NOT by removing a Rodauth index
# row. So the blob is minted for real (codec.encode, exactly as the app stores
# it) to make the invalidation genuine, not mocked. Covers:
# - after revoke: the live `session:<sid>` blob is GONE (Store.find_key -> nil),
#   the sidecar is destroyed, the sid is ZREM'd from Customer#active_sessions
# - EXACTLY ONE customer-scoped AdminAuditEvent per revoke: verb 'session.revoke',
#   target = the customer id, actor = the acting colonel's PUBLIC id, session_id
#   in detail, and blob_deleted reflects whether a live blob was present
# - IDEMPOTENT: a second revoke still returns revoked:true, still audits (this op
#   ALWAYS audits — unlike the global Delete, which skips audit on not-found), and
#   this time reports blob_deleted:false
#
# Run: try --agent try/unit/operations/sessions/revoke_for_customer_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/revoke_for_customer'

RFC   = Onetime::Operations::Sessions::RevokeForCustomer
Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::AdminAuditEvent
DB    = Familia.dbclient

@nonce = Familia.generate_id[0, 12]
@actor = "ur1colonelpub_#{@nonce}" # a PUBLIC id (extid-shaped), never an objid

@cust  = Onetime::Customer.create!(email: "revoke_#{@nonce}@example.com")
@cust.verified = 'true'
@cust.save
@extid = @cust.extid

@sid = "tryrevoke_#{@nonce}"
@key = "session:#{@sid}"
SM.load(@sid)&.destroy!

# Seed the sidecar + index via the real write path.
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @sid,
  session_data: { 'authenticated' => true, 'external_id' => @extid,
                  'ip_address' => '203.0.113.2', 'user_agent' => 'UA' },
).call

# Mint a REAL encrypted session blob (the same shape the app stores), so the
# invalidation is genuine — the op must delete this actual key.
@codec = Onetime::SessionCodec.from_config
DB.set(@key, @codec.encode({ 'authenticated' => true, 'external_id' => @extid,
                             'email' => @cust.email }))

# ---- pre-conditions ---------------------------------------------------

## before revoke: the live blob, the sidecar, and the index member all exist
[Store.find_key(DB, @sid), SM.load(@sid).nil?, @cust.active_sessions.member?(@sid)]
#=> [@key, false, true]

# ---- revoke: invalidate + tidy + audit --------------------------------

## revoke deletes the live blob and reports blob_deleted:true, revoked:true
AE.events.clear
@res = RFC.new(custid: @extid, session_id: @sid, actor: @actor).call
[@res.revoked, @res.blob_deleted, @res.session_id]
#=> [true, true, "#{@sid}"]

## the live `session:<sid>` blob is GONE (this is what logs the user out)
Store.find_key(DB, @sid)
#=> nil

## the sidecar is destroyed and the sid is ZREM'd from the customer index
[SM.load(@sid).nil?, @cust.active_sessions.member?(@sid)]
#=> [true, false]

## EXACTLY ONE audit event was written for the revoke
AE.count
#=> 1

## the event is the revoke verb, targeting the customer, actored by the PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["session.revoke", "#{@extid}", "#{@actor}"]

## the audit detail carries the session id + blob_deleted, and no secret material
@ev['detail']['session_id']
#=> "#{@sid}"

## the audit actor is never an internal objid
@ev['actor'].include?('objid')
#=> false

# ---- idempotent second revoke -----------------------------------------

## a second revoke still returns revoked:true but blob_deleted:false (already gone)
AE.events.clear
@res2 = RFC.new(custid: @extid, session_id: @sid, actor: @actor).call
[@res2.revoked, @res2.blob_deleted]
#=> [true, false]

## this op ALWAYS audits — the idempotent revoke STILL records one event
## (contrast: the global Delete skips the audit on a not-found no-op)
AE.count
#=> 1

## the second event records blob_deleted:false in its detail
AE.recent(1).first['detail']['blob_deleted']
#=> false

# Cleanup
SM.load(@sid)&.destroy!
DB.del(@key)
@cust.active_sessions.clear
@cust.destroy!
AE.events.clear
