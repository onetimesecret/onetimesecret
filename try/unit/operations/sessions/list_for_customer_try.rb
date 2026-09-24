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
# - reconciliation write failures skip only their stale row and preserve the
#   readable rows; an unknown customer returns an empty Result (no raise)
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
                    'ip_address' => '203.0.113.1', 'user_agent' => 'UA',
                    'active_session_id_hmac' => "hmac_#{sid}" },
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

## resolves by extid and returns both sessions, newest (highest score) first.
## Rows are identified by session_handle (non-bearer digest), not the raw sid (F-01).
@res = LFC.new(custid: @extid).call
[@res.count, @res.sessions.map { |s| s[:session_handle] }]
#=> [2, [SM.handle_for(@sid_new), SM.handle_for(@sid_old)]]

## each row is the safe_dump allow-list shape (metadata only, no blob fields) and
## carries NO raw session_id — only its non-reversible session_handle (F-01)
@row = @res.sessions.first
[@row[:user_id], @row.key?(:session_id), @row.key?(:session_handle), @row.key?(:email), @row.key?(:token)]
#=> ["#{@extid}", false, true, false, false]

## geo_country is never Otto's '**' sentinel: a legacy sidecar that stored it
## verbatim emits nil through safe_dump (the SessionMetadata reader is the
## normalization chokepoint), while a real code passes through untouched
DB.hset(SM.dbkey(@sid_new), 'geo_country', '"**"')
DB.hset(SM.dbkey(@sid_old), 'geo_country', '"NZ"')
@geo_rows = LFC.new(custid: @extid).call.sessions.to_h { |s| [s[:session_handle], s[:geo_country]] }
[@geo_rows[SM.handle_for(@sid_new)], @geo_rows[SM.handle_for(@sid_old)]]
#=> [nil, "NZ"]

## internal join keys accompany safe rows without a second sidecar read (the
## public row is keyed by its handle; the hmac stays an internal join value)
@res.entries.to_h { |e| [e.session[:session_handle], e.active_session_id_hmac] }
#=> {SM.handle_for(@sid_new) => "hmac_#{@sid_new}", SM.handle_for(@sid_old) => "hmac_#{@sid_old}"}

## safe_dump is the public boundary: the row carries NO internal join key
@entry = @res.entries.first
[@entry.safe_dump.equal?(@entry.session), @entry.safe_dump.key?(:active_session_id_hmac)]
#=> [true, false]

## to_h is the FULL internal dump: the join key IS present (never serialized across a boundary)
@entry.to_h.key?(:active_session_id_hmac)
#=> true

## Result#safe_dump is the public projection; Result#to_h exposes internal Entry objects
[@res.safe_dump[:count], @res.safe_dump[:sessions].first.key?(:active_session_id_hmac), @res.to_h.key?(:entries)]
#=> [2, false, true]

# ---- degraded sidecar read: other sessions remain available -----------
#
# The sidecars are read in ONE pipelined load_multi batch. A batch-level
# failure (connection error, or one corrupt record raising during
# instantiation — load_multi materializes every row in one call) falls back
# to the legacy per-row loads, where each row's own failure degrades only
# that row and leaves its index member intact (a failed READ must never be
# mistaken for absence, which would self-heal-prune a live member).

## a batch failure alone degrades to per-row loads with NO visible difference:
## every readable row still lists, newest-first
SM.singleton_class.alias_method(:__lfc_real_load_multi, :load_multi)
SM.define_singleton_method(:load_multi) do |*_args|
  raise IOError, 'pipeline blew up'
end
begin
  @batch_fallback = LFC.new(custid: @extid).call
ensure
  SM.singleton_class.remove_method(:load_multi)
  SM.singleton_class.alias_method(:load_multi, :__lfc_real_load_multi)
  SM.singleton_class.remove_method(:__lfc_real_load_multi)
end
@batch_fallback.sessions.map { |s| s[:session_handle] }
#=> [SM.handle_for(@sid_new), SM.handle_for(@sid_old)]

## an unreadable sidecar (batch fails, then that row's fallback load fails too)
## skips only that row and leaves its index member intact
failing_sid = @sid_old
SM.singleton_class.alias_method(:__lfc_real_load_multi, :load_multi)
SM.define_singleton_method(:load_multi) do |*_args|
  raise IOError, 'pipeline blew up'
end
SM.singleton_class.alias_method(:__list_for_customer_real_load, :load)
SM.define_singleton_method(:load) do |sid|
  raise IOError, 'transient Valkey failure' if sid == failing_sid

  __list_for_customer_real_load(sid)
end
begin
  @degraded = LFC.new(custid: @extid).call
ensure
  SM.singleton_class.remove_method(:load_multi)
  SM.singleton_class.alias_method(:load_multi, :__lfc_real_load_multi)
  SM.singleton_class.remove_method(:__lfc_real_load_multi)
  SM.singleton_class.remove_method(:load)
  SM.singleton_class.alias_method(:load, :__list_for_customer_real_load)
  SM.singleton_class.remove_method(:__list_for_customer_real_load)
end
[@degraded.count, @degraded.sessions.map { |s| s[:session_handle] }, @cust.active_sessions.member?(@sid_old)]
#=> [1, [SM.handle_for(@sid_new)], true]

# ---- self-heal: stale index member is pruned (sidecar gone) -----------

## a sid whose sidecar is GONE gets ZREM'd and never surfaces in the result
SM.load(@sid_old)&.destroy!            # drop the sidecar, leave the index member
@before = @cust.active_sessions.member?(@sid_old)
@res2   = LFC.new(custid: @extid).call
@after  = @cust.active_sessions.member?(@sid_old)
[@before, @res2.count, @res2.sessions.map { |s| s[:session_handle] }, @after]
#=> [true, 1, [SM.handle_for(@sid_new)], false]

## a transient self-heal write failure skips its stale row without hiding readable sessions
@write_failure_sid = "trylist_write_failure_#{@nonce}"
@cust.active_sessions.add(@write_failure_sid, @ts + 200)
write_failure_sid = @write_failure_sid
@active_sessions_class = @cust.active_sessions.class
@active_sessions_class.alias_method(:__list_for_customer_real_remove, :remove)
@active_sessions_class.define_method(:remove) do |sid|
  raise IOError, 'transient Valkey write failure' if sid == write_failure_sid

  __list_for_customer_real_remove(sid)
end
begin
  @write_failure_result = LFC.new(custid: @extid).call
ensure
  @active_sessions_class.remove_method(:remove)
  @active_sessions_class.alias_method(:remove, :__list_for_customer_real_remove)
  @active_sessions_class.remove_method(:__list_for_customer_real_remove)
end
[@write_failure_result.count, @write_failure_result.sessions.map { |s| s[:session_handle] }, @cust.active_sessions.member?(@write_failure_sid)]
#=> [1, [SM.handle_for(@sid_new)], true]

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
