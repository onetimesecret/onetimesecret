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
#
# Run: try --agent try/unit/operations/sessions_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/list_sessions'
require 'onetime/operations/sessions/inspect_session'
require 'onetime/operations/sessions/delete_session'

AE  = Onetime::AdminAuditEvent
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

# ---- List -------------------------------------------------------------

## List returns a Result whose sessions include the seeded pair
@list = Onetime::Operations::Sessions::List.new(page: 1, per_page: 50).call
ids   = @list.sessions.map { |s| s[:session_id] }
[ids.include?(@sid_a), ids.include?(@sid_b)]
#=> [true, true]

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

# ---- List: search filter ----------------------------------------------

## a search term matches only the session whose identity contains it
@found = Onetime::Operations::Sessions::List.new(search: "alice+#{@nonce}").call
@found.sessions.map { |s| s[:session_id] }
#=> ["#{@sid_a}"]

## a non-matching search term returns nothing
Onetime::Operations::Sessions::List.new(search: "nobody_#{@nonce}").call.sessions
#=> []

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

## the audit event is the delete verb, targeting the session id, actored by the PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["session.delete", "#{@sid_a}", "ur1colonelpub"]

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

# Cleanup
DB.del(@key_a)
DB.del(@key_b)
AE.events.clear
