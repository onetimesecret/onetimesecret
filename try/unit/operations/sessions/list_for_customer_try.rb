# try/unit/operations/sessions/list_for_customer_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the sidecar READ op (spec docs/specs/colonel-ui/40-*):
#   Onetime::Operations::Sessions::ListForCustomer
#
# The O(sessions-for-this-user) alternative to the GLOBAL console (no scan, no
# decrypt). Covers:
# - resolves the customer by extid and returns rows via safe_dump, NEWEST-FIRST
#   (revrange by last_activity score)
# - each row is the safe_dump allow-list shape (metadata only)
# - SELF-HEAL (sidecar gone): a sid whose sidecar is TTL-expired / destroyed is
#   ZREM'd from active_sessions and does NOT appear in the result
# - BLOB-LIVENESS RECONCILE: a sid whose sidecar is present but whose live
#   `session:<sid>` blob is gone (the 30d sidecar outliving the 24h blob) is a
#   DEAD session — the orphan sidecar is destroyed, the index member ZREM'd, and
#   the row is hidden
# - an unknown customer returns an empty Result (no raise)
#
# Run: try --agent try/unit/operations/sessions/list_for_customer_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/list_for_customer'

TM    = Onetime::Operations::Sessions::TrackMetadata
LFC   = Onetime::Operations::Sessions::ListForCustomer
Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
DB    = Familia.dbclient

@nonce = Familia.generate_id[0, 12]
@ts    = Familia.now.to_i
@codec = Onetime::SessionCodec.from_config

@cust  = Onetime::Customer.create!(email: "list_#{@nonce}@example.com")
@cust.verified = 'true'
@cust.save
@extid = @cust.extid

# Seed two sidecars via the real write path, oldest first so newest-first
# ordering is observable. active_sessions scores by last_activity epoch, so we
# stamp explicit ascending scores after tracking to make the order deterministic.
@sid_old = "trylist_old_#{@nonce}"
@sid_new = "trylist_new_#{@nonce}"
[@sid_old, @sid_new].each { |s| SM.load(s)&.destroy!; DB.del("session:#{s}") }

def track(cust, sid, extid, score)
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => extid,
                    'ip_address' => '203.0.113.1', 'user_agent' => 'UA' },
  ).call
  # Mint a REAL encrypted session blob so the blob-liveness probe sees a live
  # session (ListForCustomer prunes any sid whose `session:<sid>` blob is gone).
  DB.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                           'external_id' => extid }))
  # force a deterministic activity score for ordering
  cust.active_sessions.add(sid, score)
end

track(@cust, @sid_old, @extid, @ts)
track(@cust, @sid_new, @extid, @ts + 100)

# ---- list newest-first via safe_dump ----------------------------------

## resolves by extid and returns both sessions, newest (highest score) first
@res = LFC.new(custid: @extid).call
[@res.count, @res.sessions.map { |s| s[:session_id] }]
#=> [2, ["#{@sid_new}", "#{@sid_old}"]]

## each row is the safe_dump allow-list shape (metadata only, no blob fields)
@row = @res.sessions.first
[@row[:user_id], @row.key?(:email), @row.key?(:token)]
#=> ["#{@extid}", false, false]

# ---- self-heal: stale index member is pruned (sidecar gone) -----------

## a sid whose sidecar is GONE gets ZREM'd and never surfaces in the result
SM.load(@sid_old)&.destroy!            # drop the sidecar, leave the index member
@before = @cust.active_sessions.member?(@sid_old)
@res2   = LFC.new(custid: @extid).call
@after  = @cust.active_sessions.member?(@sid_old)
[@before, @res2.count, @res2.sessions.map { |s| s[:session_id] }, @after]
#=> [true, 1, ["#{@sid_new}"], false]

# ---- blob-liveness reconcile: dead session pruned (blob gone) ----------

## sidecar present but blob EXPIRED → row hidden, orphan sidecar destroyed, ZREM'd
DB.del("session:#{@sid_new}")          # simulate the 24h blob TTL lapsing
@sidecar_before = SM.load(@sid_new).nil?
@res3   = LFC.new(custid: @extid).call
@sidecar_after  = SM.load(@sid_new).nil?
@member_after   = @cust.active_sessions.member?(@sid_new)
[@sidecar_before, @res3.count, @res3.sessions, @sidecar_after, @member_after]
#=> [false, 0, [], true, false]

# ---- unknown customer -------------------------------------------------

## an unknown customer returns an empty Result (no raise)
@empty = LFC.new(custid: "ur_nobody_#{@nonce}").call
[@empty.count, @empty.sessions]
#=> [0, []]

# Cleanup
[@sid_old, @sid_new].each { |s| SM.load(s)&.destroy!; DB.del("session:#{s}") }
@cust.active_sessions.clear
@cust.destroy!
