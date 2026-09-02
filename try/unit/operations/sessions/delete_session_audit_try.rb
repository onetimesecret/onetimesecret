# try/unit/operations/sessions/delete_session_audit_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the AUDIT TARGET of the global session revoke (#4330):
#   Onetime::Operations::Sessions::Delete
#
# The trail used to record the raw session id. That value is the user's live
# `onetime.session` cookie, and ColonelAuditEvent.record writes into a
# count-capped set with NO TTL — so every revoke persisted a replayable bearer
# credential, indefinitely, in the one place operators are encouraged to read.
#
# RSpec stubs ColonelAuditEvent.record; these cases do a REAL write and read the
# event back, which is the only way to prove what actually lands in the trail.
# Covers the success path and the failure path (audit_failures), plus the
# no-op/not-found path that must record nothing at all.
#
# Run: try --agent try/unit/operations/sessions/delete_session_audit_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'securerandom'
require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/delete_session'

Delete = Onetime::Operations::Sessions::Delete
SM     = Onetime::SessionMetadata
AE     = Onetime::ColonelAuditEvent
DB     = Familia.dbclient

@nonce = Familia.generate_id[0, 12]
@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid

@sid    = SecureRandom.hex(32)
@key    = "session:#{@sid}"
@handle = SM.handle_for(@sid)
DB.set(@key, JSON.generate({ 'authenticated' => true, 'email' => "del+#{@nonce}@example.com" }))
AE.events.clear

## the revoke succeeds and records exactly one event
@res = Delete.new(session_id: @sid, actor: @actor).call
[@res.status, AE.count]
#=> [:deleted, 1]

## the recorded target is the 32-hex HANDLE — never the bearer sid
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'] == @handle, @ev['target'].match?(/\A[0-9a-f]{32}\z/)]
#=> ["session.delete", true, true]

## the raw sid appears NOWHERE in the serialized event
@ev.to_s.include?(@sid)
#=> false

## a not-found revoke records nothing (nothing mutated)
AE.events.clear
[Delete.new(session_id: SecureRandom.hex(32), actor: @actor).call.status, AE.count]
#=> [:not_found, 0]

## the FAILURE path (audit_failures) also records the handle, not the sid: the
## delete is made to raise mid-flight, and the event written on the way out
## carries the same non-bearer target
AE.events.clear
@fail_sid    = SecureRandom.hex(32)
@fail_handle = SM.handle_for(@fail_sid)
DB.set("session:#{@fail_sid}", JSON.generate({ 'authenticated' => true }))
@exploding = Object.new
def @exploding.exists(*_args) = 1
def @exploding.del(*_args) = raise(IOError, 'datastore went away')
begin
  Delete.new(session_id: @fail_sid, actor: @actor, dbclient: @exploding).call
rescue IOError
  nil
end
@fail_ev = AE.recent(1).first
[AE.count, @fail_ev['target'] == @fail_handle, @fail_ev['target'] == @fail_sid]
#=> [1, true, false]

# Cleanup
DB.del(@key)
DB.del("session:#{@fail_sid}")
AE.events.clear
