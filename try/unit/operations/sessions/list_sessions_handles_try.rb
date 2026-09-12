# try/unit/operations/sessions/list_sessions_handles_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the OPAQUE-HANDLE contract of the global session listing
# (#4330): Onetime::Operations::Sessions::List.
#
# The raw session id is byte-identical to the user's `onetime.session` cookie
# and to the `session:<sid>` blob key name, so it must never leave this op
# unless the caller explicitly asks. Covers:
# - default rows carry `:session_handle` and NEITHER `:session_id` NOR `:key`
# - `reveal_session_id: true` (the `bin/ots session` opt-in) restores both
# - the emitted handle is exactly SessionMetadata.handle_for(sid), so it
#   round-trips through Store.resolve_handle
# - the geo_country join still populates after the strip (it keys on the sid
#   internally, so order matters)
# - searching by a handle PREFIX returns the right row, and identity search
#   still works
#
# Run: try --agent try/unit/operations/sessions/list_sessions_handles_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'securerandom'
require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/list_sessions'
require 'onetime/operations/sessions/track_metadata'

List  = Onetime::Operations::Sessions::List
Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::ColonelAuditEvent
DB    = Familia.dbclient

@nonce = Familia.generate_id[0, 12]

# Two real 64-hex sids with identity blobs — the shape the app stores.
@sid_x = SecureRandom.hex(32)
@sid_y = SecureRandom.hex(32)
@key_x = "session:#{@sid_x}"
@key_y = "session:#{@sid_y}"
@handle_x = SM.handle_for(@sid_x)
@handle_y = SM.handle_for(@sid_y)

DB.set(@key_x, JSON.generate({
  'authenticated' => true,
  'email' => "xena+#{@nonce}@example.com",
  'external_id' => "ext_x_#{@nonce}",
  'authenticated_at' => 2_000_000_400,
}))
DB.set(@key_y, JSON.generate({
  'authenticated' => true,
  'email' => "yuri+#{@nonce}@example.com",
  'external_id' => "ext_y_#{@nonce}",
  'authenticated_at' => 2_000_000_500,
}))
AE.events.clear

## the DEFAULT listing identifies a session by handle only — the bearer sid and
## its Redis key are stripped before the rows leave the op
@row = List.new(page: 1, per_page: 100).call.sessions.find { |s| s[:session_handle] == @handle_x }
[@row.nil?, @row&.key?(:session_id), @row&.key?(:key)]
#=> [false, false, false]

## the emitted handle is exactly SessionMetadata.handle_for — the same value the
## per-customer panel already speaks — so it resolves back to the sid
[@row[:session_handle] == @handle_x, Store.resolve_handle(DB, @row[:session_handle]).first == @sid_x]
#=> [true, true]

## the row still carries its identity fields (the strip is surgical)
[@row[:email], @row[:external_id]]
#=> ["xena+#{@nonce}@example.com", "ext_x_#{@nonce}"]

## reveal_session_id: true (the `bin/ots session` opt-in) restores BOTH internal
## identifiers alongside the handle
@revealed = List.new(page: 1, per_page: 100, reveal_session_id: true)
  .call.sessions.find { |s| s[:session_handle] == @handle_x }
[@revealed[:session_id], @revealed[:key], @revealed[:session_handle]]
#=> [@sid_x, @key_x, @handle_x]

## the geo_country join survives the strip: it keys on the sid internally, so it
## must run BEFORE the identifiers are removed
SM.new(session_id: @sid_y, geo_country: 'FR').save
@geo_row = List.new(page: 1, per_page: 100).call.sessions.find { |s| s[:session_handle] == @handle_y }
[@geo_row[:geo_country], @geo_row.key?(:session_id)]
#=> ["FR", false]

## searching by a handle PREFIX finds exactly that session — the console renders
## a truncated handle, so a prefix is all an operator can copy
@by_prefix = List.new(search: @handle_x[0, 10], per_page: 100).call.sessions
[@by_prefix.size, @by_prefix.first[:session_handle]]
#=> [1, @handle_x]

## the FULL handle works too
List.new(search: @handle_x, per_page: 100).call.sessions.map { |s| s[:session_handle] }
#=> [@handle_x]

## identity search is unaffected
List.new(search: "yuri+#{@nonce}", per_page: 100).call.sessions.map { |s| s[:session_handle] }
#=> [@handle_y]

## listing is read-only: no audit event, handles or not
AE.count
#=> 0

# Cleanup
DB.del(@key_x)
DB.del(@key_y)
DB.del(SM.dbkey(@sid_y))
AE.events.clear
