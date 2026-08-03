# try/unit/models/colonel_audit_event_try.rb
#
# frozen_string_literal: true

#
# Unit tests for ColonelAuditEvent — the single write path every mutating admin
# operation calls. Covers:
# - record on success and on failure (both persisted)
# - best-effort semantics (a write error never raises to the caller)
# - newest-first read path (recent)
# - capped sorted-set trimming (count bound enforced)
# - actor normalization (extid/email, never internal objid)
# - detail redaction (secrets/tokens/passphrases never stored)
# - the separate security-telemetry trail (record_security): its own collection,
#   its own count cap and age bound, and the invariant that flooding it cannot
#   evict operator records

require_relative '../../support/test_models'

OT.boot! :test

# Isolate: this is a single global sorted set, so clear it before/after.
ColonelAuditEvent.events.clear

# TRYOUTS

## events is a Familia::SortedSet
ColonelAuditEvent.events.class
#=> Familia::SortedSet

## backing store key is the global colonel_audit_event:events set
ColonelAuditEvent.events.dbkey
#=> "colonel_audit_event:events"

## record persists a success event and returns the stored hash
event = ColonelAuditEvent.record(
  actor: 'ur7xexamples',
  verb: 'customer.set_role',
  target: 'ur9ytargets',
  result: :success,
  detail: { role: 'colonel' },
)
[event['actor'], event['verb'], event['target'], event['result'], event['detail']]
#=> ["ur7xexamples", "customer.set_role", "ur9ytargets", "success", { "role" => "colonel" }]

## the success event landed in the backing set
ColonelAuditEvent.count
#=> 1

## record persists a failure event too (both success and failure are recorded)
ColonelAuditEvent.record(
  actor: 'ur7xexamples',
  verb: 'customer.purge',
  target: 'ur9ytargets',
  result: :failure,
  detail: { reason: 'not_found' },
)
ColonelAuditEvent.count
#=> 2

## recent returns events newest-first
ColonelAuditEvent.recent(2).map { |e| e['verb'] }
#=> ["customer.purge", "customer.set_role"]

## recorded events carry a creation timestamp (float epoch seconds)
ColonelAuditEvent.recent(1).first['created'].is_a?(Float)
#=> true

## each event has a unique nonce id so identical events never collide
ColonelAuditEvent.events.clear
2.times do
  ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success)
end
ColonelAuditEvent.count
#=> 2

## record is best-effort: an error during the write returns nil, never raises
# A detail value whose #to_s raises forces an exception inside record; the
# best-effort rescue must swallow it and return nil so the caller op is unharmed.
ColonelAuditEvent.events.clear
class Boom
  def to_s
    raise 'boom serializing detail'
  end
end
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: Boom.new)
#=> nil

## a failed write leaves the set untouched
ColonelAuditEvent.count
#=> 0

## normalize_actor prefers a Customer-like object's extid over its email/objid
ColonelAuditEvent.events.clear
fake_customer = Struct.new(:extid, :email, :objid).new('ur1publics', 'colonel@example.com', 'objid_internal_secret')
@ev = ColonelAuditEvent.record(actor: fake_customer, verb: 'v', target: 't', result: :success)
@ev['actor']
#=> "ur1publics"

## normalize_actor never stores an internal objid
@ev['actor'].include?('objid_internal')
#=> false

## normalize_actor falls back to email when extid is blank
blank_extid = Struct.new(:extid, :email).new('', 'colonel@example.com')
ColonelAuditEvent.record(actor: blank_extid, verb: 'v', target: 't', result: :success)['actor']
#=> "colonel@example.com"

## redaction blanks sensitive keys (passphrase, token, secret, password) at any depth
ColonelAuditEvent.events.clear
redacted = ColonelAuditEvent.record(
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
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: { 'blob' => long })['detail']['blob'].length
#=> 259

## trim! enforces the count cap: keep only the newest N, drop the oldest overflow
ColonelAuditEvent.events.clear
5.times { |i| ColonelAuditEvent.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }
removed = ColonelAuditEvent.trim!(3)
[removed, ColonelAuditEvent.count]
#=> [2, 3]

## trimming keeps the newest events (v2, v3, v4 survive; v0, v1 dropped)
ColonelAuditEvent.recent(3).map { |e| e['verb'] }
#=> ["v4", "v3", "v2"]

## trim! is a no-op when the set is already at or under the cap
ColonelAuditEvent.trim!(10)
#=> 0

## record auto-trims to MAX_EVENTS on every write (count never exceeds the cap)
ColonelAuditEvent.events.clear
ColonelAuditEvent::MAX_EVENTS >= ColonelAuditEvent.count
#=> true

## recent(0) returns an empty array
ColonelAuditEvent.recent(0)
#=> []

## -- Security trail: a SEPARATE retention domain -------------------------
#
# The operator trail is count-capped with no TTL and evicts oldest-first, so a
# writer an unauthenticated caller can drive would be a log-eviction primitive.
# record_security writes to its own collection with its own budget; these cases
# pin that the two never share storage.

## security_events is a distinct backing set, not the operator trail
ColonelAuditEvent.security_events.dbkey
#=> "colonel_audit_event:security_events"

## record_security stores the same event shape
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
@sec = ColonelAuditEvent.record_security(
  actor: 'anonymous',
  verb: 'auth.reset_request_throttled',
  target: 'ip:203.0.x.x',
  result: :failure,
  detail: { 'tier' => 'ip' },
)
[@sec['actor'], @sec['verb'], @sec['result'], @sec['detail']]
#=> ["anonymous", "auth.reset_request_throttled", "failure", { "tier" => "ip" }]

## a security write NEVER lands in the operator trail (the eviction boundary)
[ColonelAuditEvent.count, ColonelAuditEvent.security_count]
#=> [0, 1]

## conversely, an operator write never lands in the security trail
ColonelAuditEvent.record(actor: 'ur7xexamples', verb: 'customer.purge', target: 't', result: :success)
[ColonelAuditEvent.count, ColonelAuditEvent.security_count]
#=> [1, 1]

## flooding the security trail past its cap evicts NOTHING from the operator
## trail — the whole point of the split
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.trim_security!(3)
5.times { |i| ColonelAuditEvent.record_security(actor: 'anonymous', verb: "s#{i}", target: 't', result: :failure) }
ColonelAuditEvent.trim_security!(3)
[ColonelAuditEvent.security_count, ColonelAuditEvent.count]
#=> [3, 1]

## security trimming keeps the newest (oldest overflow dropped)
ColonelAuditEvent.recent_security(3).map { |e| e['verb'] }
#=> ["s4", "s3", "s2"]

## the security trail also has an AGE bound (the operator trail has none):
## members scored older than max_age are removed by score
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.security_events.add({ 'verb' => 'stale' }, Familia.now - 100)
ColonelAuditEvent.security_events.add({ 'verb' => 'fresh' }, Familia.now)
removed = ColonelAuditEvent.trim_security!(ColonelAuditEvent::MAX_SECURITY_EVENTS, 50)
[removed, ColonelAuditEvent.recent_security(5).map { |e| e['verb'] }]
#=> [1, ["fresh"]]

## a non-positive max_age disables only the age pass; the count cap still holds
ColonelAuditEvent.security_events.clear
3.times { |i| ColonelAuditEvent.security_events.add({ 'verb' => "n#{i}" }, Familia.now - 1000 + i) }
[ColonelAuditEvent.trim_security!(2, 0), ColonelAuditEvent.security_count]
#=> [1, 2]

## recent_security(0) returns an empty array
ColonelAuditEvent.recent_security(0)
#=> []

# Cleanup
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
