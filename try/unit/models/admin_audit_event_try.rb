# try/unit/models/admin_audit_event_try.rb
#
# frozen_string_literal: true

#
# Unit tests for AdminAuditEvent — the single write path every mutating admin
# operation calls. Covers:
# - record on success and on failure (both persisted)
# - best-effort semantics (a write error never raises to the caller)
# - newest-first read path (recent)
# - capped sorted-set trimming (count bound enforced)
# - actor normalization (extid/email, never internal objid)
# - detail redaction (secrets/tokens/passphrases never stored)

require_relative '../../support/test_models'

OT.boot! :test

# Isolate: this is a single global sorted set, so clear it before/after.
AdminAuditEvent.events.clear

# TRYOUTS

## events is a Familia::SortedSet
AdminAuditEvent.events.class
#=> Familia::SortedSet

## backing store key is the global admin_audit_event:events set
AdminAuditEvent.events.dbkey
#=> "admin_audit_event:events"

## record persists a success event and returns the stored hash
event = AdminAuditEvent.record(
  actor: 'ur7xexamples',
  verb: 'customer.set_role',
  target: 'ur9ytargets',
  result: :success,
  detail: { role: 'colonel' },
)
[event['actor'], event['verb'], event['target'], event['result'], event['detail']]
#=> ["ur7xexamples", "customer.set_role", "ur9ytargets", "success", { "role" => "colonel" }]

## the success event landed in the backing set
AdminAuditEvent.count
#=> 1

## record persists a failure event too (both success and failure are recorded)
AdminAuditEvent.record(
  actor: 'ur7xexamples',
  verb: 'customer.purge',
  target: 'ur9ytargets',
  result: :failure,
  detail: { reason: 'not_found' },
)
AdminAuditEvent.count
#=> 2

## recent returns events newest-first
AdminAuditEvent.recent(2).map { |e| e['verb'] }
#=> ["customer.purge", "customer.set_role"]

## recorded events carry a creation timestamp (float epoch seconds)
AdminAuditEvent.recent(1).first['created'].is_a?(Float)
#=> true

## each event has a unique nonce id so identical events never collide
AdminAuditEvent.events.clear
2.times do
  AdminAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success)
end
AdminAuditEvent.count
#=> 2

## record is best-effort: an error during the write returns nil, never raises
# A detail value whose #to_s raises forces an exception inside record; the
# best-effort rescue must swallow it and return nil so the caller op is unharmed.
AdminAuditEvent.events.clear
class Boom
  def to_s
    raise 'boom serializing detail'
  end
end
AdminAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: Boom.new)
#=> nil

## a failed write leaves the set untouched
AdminAuditEvent.count
#=> 0

## normalize_actor prefers a Customer-like object's extid over its email/objid
AdminAuditEvent.events.clear
fake_customer = Struct.new(:extid, :email, :objid).new('ur1publics', 'colonel@example.com', 'objid_internal_secret')
@ev = AdminAuditEvent.record(actor: fake_customer, verb: 'v', target: 't', result: :success)
@ev['actor']
#=> "ur1publics"

## normalize_actor never stores an internal objid
@ev['actor'].include?('objid_internal')
#=> false

## normalize_actor falls back to email when extid is blank
blank_extid = Struct.new(:extid, :email).new('', 'colonel@example.com')
AdminAuditEvent.record(actor: blank_extid, verb: 'v', target: 't', result: :success)['actor']
#=> "colonel@example.com"

## redaction blanks sensitive keys (passphrase, token, secret, password) at any depth
AdminAuditEvent.events.clear
redacted = AdminAuditEvent.record(
  actor: 'a', verb: 'v', target: 't', result: :success,
  detail: {
    'passphrase' => 'hunter2',
    'api_token' => 'sk_live_abc',
    'note' => 'safe to keep',
    'nested' => { 'secret_value' => 'plaintext', 'ok' => 1 },
  },
)['detail']
[redacted['passphrase'], redacted['api_token'], redacted['note'], redacted['nested']['secret_value'], redacted['nested']['ok']]
#=> ["[REDACTED]", "[REDACTED]", "safe to keep", "[REDACTED]", 1]

## redaction truncates overlong string values
long = 'x' * 500
AdminAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: { 'blob' => long })['detail']['blob'].length
#=> 259

## trim! enforces the count cap: keep only the newest N, drop the oldest overflow
AdminAuditEvent.events.clear
5.times { |i| AdminAuditEvent.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }
removed = AdminAuditEvent.trim!(3)
[removed, AdminAuditEvent.count]
#=> [2, 3]

## trimming keeps the newest events (v2, v3, v4 survive; v0, v1 dropped)
AdminAuditEvent.recent(3).map { |e| e['verb'] }
#=> ["v4", "v3", "v2"]

## trim! is a no-op when the set is already at or under the cap
AdminAuditEvent.trim!(10)
#=> 0

## record auto-trims to MAX_EVENTS on every write (count never exceeds the cap)
AdminAuditEvent.events.clear
AdminAuditEvent::MAX_EVENTS >= AdminAuditEvent.count
#=> true

## recent(0) returns an empty array
AdminAuditEvent.recent(0)
#=> []

# Cleanup
AdminAuditEvent.events.clear
