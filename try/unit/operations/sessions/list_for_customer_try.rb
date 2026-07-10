# try/unit/operations/sessions/list_for_customer_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the sidecar READ op (spec docs/specs/colonel-ui/40-*):
#   Onetime::Operations::Sessions::ListForCustomer
#
# The O(sessions-for-this-user) alternative to the GLOBAL console (no scan, no
# decrypt, no blob read). Covers:
# - resolves the customer by extid and returns rows via safe_dump, NEWEST-FIRST
#   (revrange by last_activity score)
# - each row is the safe_dump allow-list shape (metadata only)
# - SELF-HEAL: a sid whose sidecar is gone (TTL-expired / revoked out-of-band) is
#   ZREM'd from active_sessions and does NOT appear in the result
# - an unknown customer returns an empty Result (no raise)
#
# Run: try --agent try/unit/operations/sessions/list_for_customer_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/list_for_customer'

TM  = Onetime::Operations::Sessions::TrackMetadata
LFC = Onetime::Operations::Sessions::ListForCustomer
SM  = Onetime::SessionMetadata

@nonce = Familia.generate_id[0, 12]
@ts    = Familia.now.to_i

@cust  = Onetime::Customer.create!(email: "list_#{@nonce}@example.com")
@cust.verified = 'true'
@cust.save
@extid = @cust.extid

# Seed two sidecars via the real write path, oldest first so newest-first
# ordering is observable. active_sessions scores by last_activity epoch, so we
# stamp explicit ascending scores after tracking to make the order deterministic.
@sid_old = "trylist_old_#{@nonce}"
@sid_new = "trylist_new_#{@nonce}"
[@sid_old, @sid_new].each { |s| SM.load(s)&.destroy! }

def track(cust, sid, extid, score)
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => extid,
                    'ip_address' => '203.0.113.1', 'user_agent' => 'UA' },
  ).call
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

# ---- self-heal: stale index member is pruned --------------------------

## a sid whose sidecar is GONE gets ZREM'd and never surfaces in the result
SM.load(@sid_old)&.destroy!            # drop the sidecar, leave the index member
@before = @cust.active_sessions.member?(@sid_old)
@res2   = LFC.new(custid: @extid).call
@after  = @cust.active_sessions.member?(@sid_old)
[@before, @res2.count, @res2.sessions.map { |s| s[:session_id] }, @after]
#=> [true, 1, ["#{@sid_new}"], false]

# ---- unknown customer -------------------------------------------------

## an unknown customer returns an empty Result (no raise)
@empty = LFC.new(custid: "ur_nobody_#{@nonce}").call
[@empty.count, @empty.sessions]
#=> [0, []]

# Cleanup
[@sid_old, @sid_new].each { |s| SM.load(s)&.destroy! }
@cust.active_sessions.clear
@cust.destroy!
