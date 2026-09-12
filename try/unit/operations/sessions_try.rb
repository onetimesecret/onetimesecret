# try/unit/operations/sessions_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted session admin operations (epic #40):
#   Onetime::Operations::Sessions::{List, Inspect, Delete}
#
# These are the SINGLE implementation of the session list / inspect / delete
# verbs (the colonel API + `bin/ots session *` CLI are thin adapters). Covers:
# - List: bounded scan → summaries, newest-first, in-memory pagination
# - List search: free-text identity filter (email / external_id)
# - Inspect: resolves a live session (data + ttl); miss returns found:false
# - Delete: removes the key, returns :deleted, records EXACTLY ONE audit event
#   (verb session.delete, actor = PUBLIC id, target = session id)
# - Delete not-found: revoking a non-existent session is a no-op (:not_found, NO audit)
# - Store: opaque session handles (#4330) — summarize emits one, resolve_handle
#   round-trips it back to a sid (owner-hinted first, bounded scan second), and
#   matches_search? matches a handle prefix
#
# The List cases below pass `reveal_session_id: true` wherever they assert on
# `:session_id` / `:key`: those identifiers are the bearer cookie value and are
# stripped by default (#4330). The default, HTTP-facing shape is covered in
# try/unit/operations/sessions/list_sessions_handles_try.rb.
#
# Run: try --agent try/unit/operations/sessions_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'securerandom'
require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/list_sessions'
require 'onetime/operations/sessions/inspect_session'
require 'onetime/operations/sessions/delete_session'
require 'onetime/session/sidecar'

AE  = Onetime::ColonelAuditEvent
DB  = Familia.dbclient

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid

# Unique, collision-proof ids for this run.
@nonce = Familia.generate_id[0, 12]
@sid_a = "trysess_a_#{@nonce}"
@sid_b = "trysess_b_#{@nonce}"
@key_a = "session:#{@sid_a}"
@key_b = "session:#{@sid_b}"

@data_a = {
  'authenticated' => true,
  'email' => "alice+#{@nonce}@example.com",
  'external_id' => "ext_a_#{@nonce}",
  'authenticated_at' => 2_000_000_100,
}
@data_b = {
  'authenticated' => false,
  'email' => "bob+#{@nonce}@example.com",
  'external_id' => "ext_b_#{@nonce}",
  'authenticated_at' => 2_000_000_200,
}

# Clean slate + seed two sessions as JSON (how the app stores them).
DB.del(@key_a)
DB.del(@key_b)
DB.set(@key_a, JSON.generate(@data_a))
DB.set(@key_b, JSON.generate(@data_b))
AE.events.clear

# Plant a NON-STRING key matching the session scan pattern — the shape the
# colonel entitlement-preview writes (session:<sid>:entitlement_preview_*, a
# Redis SET). Regression guard for the QA 2026-07-07 finding: one such key
# made EVERY listing 500 (GET on it raises WRONGTYPE, and the read ran outside
# any rescue). All List cases below run with this key present.
@set_key = "session:#{@nonce}:entitlement_preview_grants"
DB.del(@set_key)
DB.sadd(@set_key, %w[api_access custom_domains])

# Plant a per-value sidecar STRING key (sidecar:<64-hex-sid>:<field>, issue
# #3858). Unlike the preview SET above, it IS a string, so a `session:`-
# namespaced name would sail through the scan's `type: 'string'` filter into
# every listing/count — which is exactly why the sidecar prefix lives OUTSIDE
# the `*session*` match. All List cases below run with this key present too.
@sidecar_sid = SecureRandom.hex(32)
@sidecar_key = "sidecar:#{@sidecar_sid}:awaiting_mfa"
DB.del(@sidecar_key)
DB.set(@sidecar_key, 'sidecar-envelope-bytes')

# ---- List -------------------------------------------------------------

## List returns a Result whose sessions include the seeded pair
## (with the non-string session:* key planted — see the regression note above)
@list = Onetime::Operations::Sessions::List.new(page: 1, per_page: 50, reveal_session_id: true).call
ids   = @list.sessions.map { |s| s[:session_id] }
[ids.include?(@sid_a), ids.include?(@sid_b)]
#=> [true, true]

## [regression] the non-string key never surfaces as a listing row
@list.sessions.map { |s| s[:key] }.include?(@set_key)
#=> false

## [regression] Store.scan_keys filters non-string keys out server-side (SCAN TYPE)
Onetime::Operations::Sessions::Store.scan_keys(DB).include?(@set_key)
#=> false

## [regression] Store.load_data on a non-string key resolves nil instead of raising WRONGTYPE
Onetime::Operations::Sessions::Store.load_data(DB, @set_key)
#=> nil

## [#3858] a sidecar STRING key never surfaces as a listing row — its
## `sidecar:` prefix keeps it outside the `*session*` scan by construction,
## with no client-side reject anywhere
@list.sessions.map { |s| s[:key] }.include?(@sidecar_key)
#=> false

## [#3858] Store.scan_keys never sees sidecar keys: the namespace is disjoint,
## so every scan consumer (List, count, the revoke sweeps) stays clean and
## `keys.size >= MAX_SCAN` remains an exact truncation signal
Onetime::Operations::Sessions::Store.scan_keys(DB).include?(@sidecar_key)
#=> false

## [#3858] the planted key matches SessionSidecar's real derivation, and the
## derived name must never match the `*session*` scan glob — i.e. the prefix
## must never contain the substring "session". This is the property the whole
## scan exclusion rests on; renaming the prefix back into the session
## namespace fails here first. (File.fnmatch mirrors the Redis MATCH glob.)
[
  Onetime::SessionSidecar.key_for(@sidecar_sid, 'awaiting_mfa') == @sidecar_key,
  File.fnmatch?('*session*', Onetime::SessionSidecar.key_for(@sidecar_sid, 'awaiting_mfa')),
]
#=> [true, false]

## Store.count tallies string session keys via the same bounded scan (>= the seeded pair)
Onetime::Operations::Sessions::Store.count(DB) >= 2
#=> true

## List surfaces the summary fields (authenticated flag + email + external id)
@row_a = @list.sessions.find { |s| s[:session_id] == @sid_a }
[@row_a[:authenticated], @row_a[:email], @row_a[:external_id]]
#=> [true, "alice+#{@nonce}@example.com", "ext_a_#{@nonce}"]

## List is read-only — no audit event recorded
AE.count
#=> 0

## List sorts newest-authenticated first (b at 200 precedes a at 100)
subset = @list.sessions.select { |s| [@sid_a, @sid_b].include?(s[:session_id]) }.map { |s| s[:session_id] }
subset
#=> ["#{@sid_b}", "#{@sid_a}"]

# ---- List: geo_country decoration (ONE batched sidecar read) -----------

## the page is decorated from the metadata sidecar via a single pipelined
## load_multi: a sidecar with a code decorates its row; a legacy sidecar that
## stored Otto's '**' sentinel decorates as nil (SessionMetadata#geo_country
## is the normalization chokepoint); a session with NO sidecar still lists,
## with nil — absence never prunes and never raises
Onetime::SessionMetadata.new(session_id: @sid_a, geo_country: 'US').save
DB.hset(Onetime::SessionMetadata.dbkey(@sid_b), 'geo_country', '"**"')
@sid_c = "trysess_c_#{@nonce}"
DB.set("session:#{@sid_c}", JSON.generate(
  @data_a.merge('external_id' => "ext_c2_#{@nonce}", 'email' => "cyn+#{@nonce}@example.com"),
))
@geo_map = Onetime::Operations::Sessions::List.new(page: 1, per_page: 50, reveal_session_id: true).call
  .sessions.to_h { |s| [s[:session_id], s[:geo_country]] }
[@geo_map[@sid_a], @geo_map[@sid_b], @geo_map.key?(@sid_c), @geo_map[@sid_c]]
#=> ["US", nil, true, nil]

## a batch-level sidecar read failure (load_multi raising) degrades to the
## legacy per-row loads — decoration is identical, the listing never dies
Onetime::SessionMetadata.singleton_class.alias_method(:__list_real_load_multi, :load_multi)
Onetime::SessionMetadata.define_singleton_method(:load_multi) do |*_args|
  raise IOError, 'pipeline blew up'
end
begin
  @fb_map = Onetime::Operations::Sessions::List.new(page: 1, per_page: 50, reveal_session_id: true).call
    .sessions.to_h { |s| [s[:session_id], s[:geo_country]] }
ensure
  Onetime::SessionMetadata.singleton_class.remove_method(:load_multi)
  Onetime::SessionMetadata.singleton_class.alias_method(:load_multi, :__list_real_load_multi)
  Onetime::SessionMetadata.singleton_class.remove_method(:__list_real_load_multi)
end
DB.del("session:#{@sid_c}")
[@fb_map[@sid_a], @fb_map[@sid_b], @fb_map[@sid_c]]
#=> ["US", nil, nil]

# ---- List: search filter ----------------------------------------------

## a search term matches only the session whose identity contains it
@found = Onetime::Operations::Sessions::List.new(search: "alice+#{@nonce}", reveal_session_id: true).call
@found.sessions.map { |s| s[:session_id] }
#=> ["#{@sid_a}"]

## a non-matching search term returns nothing
Onetime::Operations::Sessions::List.new(search: "nobody_#{@nonce}").call.sessions
#=> []

# ---- Decrypt path + anonymous filtering -------------------------------

## Store.load_data decrypts an ENCRYPTED session blob when given a codec
## (the app stores blobs, not plaintext JSON — without the codec every value
## fell through to the opaque _raw fallback and showed as Anonymous)
@codec   = Onetime::SessionCodec.from_config
@enc_sid = "trysess_enc_#{@nonce}"
@enc_key = "session:#{@enc_sid}"
@enc_data = {
  'authenticated' => true,
  'email' => "carol+#{@nonce}@example.com",
  'account_id' => 99,
  'external_id' => "ext_c_#{@nonce}",
  'authenticated_at' => 2_000_000_300,
}
DB.set(@enc_key, @codec.encode(@enc_data))
Onetime::Operations::Sessions::Store.load_data(DB, @enc_key, codec: @codec)['email']
#=> "carol+#{@nonce}@example.com"

## without the codec the SAME encrypted blob is unreadable — the _raw fallback
Onetime::Operations::Sessions::Store.load_data(DB, @enc_key).keys
#=> ['_raw']

## Store.identified? is true for a session carrying actor identity
Onetime::Operations::Sessions::Store.identified?(@enc_data)
#=> true

## Store.identified? is false for a CSRF-token-only anonymous session
Onetime::Operations::Sessions::Store.identified?({ 'csrf' => 'abc123' })
#=> false

## List HIDES a CSRF-only anonymous session but still COUNTS it as anonymous
@anon_sid = "trysess_anon_#{@nonce}"
@anon_key = "session:#{@anon_sid}"
DB.set(@anon_key, @codec.encode({ 'csrf' => "tok_#{@nonce}" }))
@flt = Onetime::Operations::Sessions::List.new(page: 1, per_page: 50, reveal_session_id: true).call
# hidden from the rows, present in the anonymous tally
[@flt.sessions.map { |s| s[:session_id] }.include?(@anon_sid), @flt.anonymous_count >= 1]
#=> [false, true]

## the decrypted identity session DOES surface in the list, with its email + user agent slot
@enc_row = @flt.sessions.find { |s| s[:session_id] == @enc_sid }
[@enc_row.nil?, @enc_row && @enc_row[:email]]
#=> [false, "carol+#{@nonce}@example.com"]

## List reports the keyspace shape: scanned tally and an uncapped bounded scan
[@flt.scanned >= 2, @flt.scan_capped]
#=> [true, false]

DB.del(@enc_key)
DB.del(@anon_key)

# ---- Inspect ----------------------------------------------------------

## Inspect resolves a live session, returning its key + parsed data
@ins = Onetime::Operations::Sessions::Inspect.new(session_id: @sid_a).call
[@ins.found, @ins.key, @ins.data['email']]
#=> [true, "session:#{@sid_a}", "alice+#{@nonce}@example.com"]

## Inspect is read-only — still no audit event
AE.count
#=> 0

## Inspect of an unknown id returns found:false with nil fields
@miss = Onetime::Operations::Sessions::Inspect.new(session_id: "no_such_#{@nonce}").call
[@miss.found, @miss.key, @miss.data]
#=> [false, nil, nil]

# ---- Delete: success --------------------------------------------------

## Delete removes the session key and returns :deleted
AE.events.clear
@del = Onetime::Operations::Sessions::Delete.new(session_id: @sid_a, actor: @actor).call
[@del.status, @del.key]
#=> [:deleted, "session:#{@sid_a}"]

## the session key is actually gone from Redis
DB.exists(@key_a)
#=> 0

## exactly ONE audit event was recorded for the delete
AE.count
#=> 1

## the audit event is the delete verb, targeting the session HANDLE (never the
## bearer sid — the trail is count-capped with no TTL, #4330), actored by the
## PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["session.delete", Onetime::SessionMetadata.handle_for(@sid_a), "ur1colonelpub"]

## the recorded target is a 32-hex handle and is NOT the raw session id
[@ev['target'].match?(/\A[0-9a-f]{32}\z/), @ev['target'] == @sid_a]
#=> [true, false]

## the audit actor is never an internal objid
@ev['actor'].include?('objid')
#=> false

# ---- Delete: not-found no-op ------------------------------------------

## revoking a non-existent session is a no-op (:not_found)
AE.events.clear
@nf = Onetime::Operations::Sessions::Delete.new(session_id: "no_such_#{@nonce}", actor: @actor).call
@nf.status
#=> :not_found

## a no-op delete records NO audit event (nothing mutated)
AE.count
#=> 0

# ---- Delete: per-value sidecar purge (#3858) --------------------------

## deleting a session also purges its per-value sidecar keys — the purge is an
## exact registry DEL, format-gated to real 64-hex sids (which is why this
## case mints a hex sid instead of the readable trysess_* ids above)
@hex_sid = SecureRandom.hex(32)
@hex_key = "session:#{@hex_sid}"
DB.set(@hex_key, JSON.generate({ 'external_id' => "ext_hex_#{@nonce}" }))
DB.set("sidecar:#{@hex_sid}:awaiting_mfa", 'x')
DB.set("sidecar:#{@hex_sid}:domain_context", 'y')
@delres = Onetime::Operations::Sessions::Delete.new(session_id: @hex_sid, actor: @actor).call
[@delres.status, DB.exists(@hex_key),
 DB.exists("sidecar:#{@hex_sid}:awaiting_mfa", "sidecar:#{@hex_sid}:domain_context")]
#=> [:deleted, 0, 0]

# ---- Store: opaque session handles (#4330) ----------------------------

## summarize emits a 32-hex handle for the session it summarizes — the ONLY
## identifier that is safe to serialize (the sid is the bearer cookie)
@h_sid    = SecureRandom.hex(32)
@h_key    = "session:#{@h_sid}"
@h_data   = { 'authenticated' => true, 'email' => "hank+#{@nonce}@example.com",
              'external_id' => "ext_h_#{@nonce}" }
@h_summary = Onetime::Operations::Sessions::Store.summarize(@h_sid, @h_key, @h_data)
[@h_summary[:session_handle] == Onetime::SessionMetadata.handle_for(@h_sid),
 @h_summary[:session_handle].match?(/\A[0-9a-f]{32}\z/)]
#=> [true, true]

## resolve_handle round-trips a handle back to its sid through the bounded scan
## (no owner hint), reporting an uncapped scan
DB.set(@h_key, JSON.generate(@h_data))
Onetime::Operations::Sessions::Store.resolve_handle(DB, @h_summary[:session_handle])
#=> [@h_sid, false]

## the handle is case-insensitive on the way in (operators paste)
Onetime::Operations::Sessions::Store.resolve_handle(DB, @h_summary[:session_handle].upcase).first
#=> @h_sid

## a malformed handle never touches the datastore: it fails the shape guard and
## answers [nil, false] — which is why the API can 404 it exactly like an
## unknown handle, with no oracle for a scanner
Onetime::Operations::Sessions::Store.resolve_handle(DB, 'not-a-handle')
#=> [nil, false]

## a well-formed but unknown handle answers [nil, capped] — the truncation flag
## rides along so a caller can say "not sampled" instead of "does not exist"
Onetime::Operations::Sessions::Store.resolve_handle(DB, 'f' * 32)
#=> [nil, false]

## the OWNER-HINTED stage never scans the keyspace: with the customer's own
## active_sessions holding the sid, resolution succeeds even while scan_keys is
## stubbed to explode (proving stage 2 was not reached)
@hint_cust = Onetime::Customer.create!(email: "handle_#{@nonce}@example.com")
@hint_cust.verified = 'true'
@hint_cust.save
@hint_sid = SecureRandom.hex(32)
@hint_cust.active_sessions.add(@hint_sid, Familia.now.to_i)
@hint_handle = Onetime::SessionMetadata.handle_for(@hint_sid)
Store = Onetime::Operations::Sessions::Store unless defined?(Store)
Store.singleton_class.alias_method(:__real_scan_keys, :scan_keys)
Store.define_singleton_method(:scan_keys) { |*_args, **_kw| raise 'scan must not run' }
begin
  @hinted = Store.resolve_handle(DB, @hint_handle, owner_hint: @hint_cust.extid)
ensure
  Store.singleton_class.remove_method(:scan_keys)
  Store.singleton_class.alias_method(:scan_keys, :__real_scan_keys)
  Store.singleton_class.remove_method(:__real_scan_keys)
end
@hinted
#=> [@hint_sid, false]

## a WRONG owner hint is not authorization — it only picks a cheaper search
## space, so resolution falls through to the bounded scan and still finds it
Onetime::Operations::Sessions::Store.resolve_handle(
  DB, @h_summary[:session_handle], owner_hint: @hint_cust.extid,
).first
#=> @h_sid

## matches_search? matches a handle PREFIX when the sid is supplied (the console
## renders a truncated handle, so a prefix is what an operator can copy)
[Onetime::Operations::Sessions::Store.matches_search?(
   @h_data, @h_summary[:session_handle][0, 8], session_id: @h_sid),
 Onetime::Operations::Sessions::Store.matches_search?(
   @h_data, @h_summary[:session_handle], session_id: @h_sid)]
#=> [true, true]

## a handle-shaped needle that is not THIS session's handle does not match
Onetime::Operations::Sessions::Store.matches_search?(
  @h_data, 'deadbeef', session_id: @h_sid,
)
#=> false

## identity search is unchanged, with or without the sid keyword (the CLI
## caller still passes none)
[Onetime::Operations::Sessions::Store.matches_search?(@h_data, "hank+#{@nonce}"),
 Onetime::Operations::Sessions::Store.matches_search?(@h_data, "ext_h_#{@nonce}", session_id: @h_sid)]
#=> [true, true]

# ---- Store.extract_id: recover the bare sid from every key shape (#3858) ----

## extract_id strips the prefix from each supported key shape down to the bare
## sid — critically the nested `session:rack:session:<sid>` shape, where a
## single strip would leave `rack:session:<sid>` and make the sidecar purge (a
## format-gated no-op on non-hex sids) silently skip the session's sidecars
@eid = SecureRandom.hex(32)
[
  Onetime::Operations::Sessions::Store.extract_id("session:#{@eid}"),
  Onetime::Operations::Sessions::Store.extract_id("rack:session:#{@eid}"),
  Onetime::Operations::Sessions::Store.extract_id(@eid),
  Onetime::Operations::Sessions::Store.extract_id("session:rack:session:#{@eid}"),
].uniq
#=> [@eid]

# Cleanup
DB.del(@key_a)
DB.del(@key_b)
# Sidecar fixtures: delete by key, not load+destroy! — the @sid_b sidecar was
# planted via raw HSET with only a geo_country field, so a loaded instance has
# no identifier and destroy! would raise.
DB.del(Onetime::SessionMetadata.dbkey(@sid_a))
DB.del(Onetime::SessionMetadata.dbkey(@sid_b))
DB.del(@set_key)
DB.del(@sidecar_key)
DB.del(@hex_key)
# The planted sidecar fixtures have NO TTL and live outside the `*session*`
# scan, so if the Delete op's purge ever regresses these would leak as
# immortal keys no sweep reclaims — delete them explicitly (same convention
# as the revoke_* tryouts' teardowns).
DB.del("sidecar:#{@hex_sid}:awaiting_mfa")
DB.del("sidecar:#{@hex_sid}:domain_context")
DB.del(@h_key)
@hint_cust.active_sessions.clear
@hint_cust.destroy!
AE.events.clear
