# try/unit/models/colonel_audit_event_try.rb
#
# frozen_string_literal: true

#
# Unit tests for ColonelAuditEvent — the single write path every mutating admin
# operation calls. Covers:
# - record on success and on failure (both persisted)
# - best-effort semantics (a write error never raises to the caller)
# - fail-closed semantics for destructive verbs (#4333): the same write error
#   raises Onetime::AuditWriteFailure when the caller opts in
# - newest-first read path (recent)
# - capped sorted-set trimming (count bound enforced)
# - actor normalization (extid/email, never internal objid)
# - detail redaction (secrets/tokens/passphrases never stored)
# - the separate security-telemetry trail (record_security): its own collection,
#   its own count cap and age bound, and the invariant that flooding it cannot
#   evict operator records
# - the separate OBSERVATION trail (record_access, #4335): the same, one step
#   further — authenticated but chatty writers get their own budget too

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

## -- Fail-closed for destructive verbs (#4333) ---------------------------
#
# Same simulated write failure as above; the only difference is the caller's
# opt-in. Destructive verbs must not report success for an action with no
# trail, so they get an exception instead of a nil.

## fail_closed: true raises Onetime::AuditWriteFailure instead of returning nil
begin
  ColonelAuditEvent.record(
    actor: 'a', verb: 'customer.purge', target: 'ur9ytargets', result: :success,
    detail: Boom.new, fail_closed: true,
  )
  :no_raise
rescue Onetime::AuditWriteFailure => ex
  [ex.verb, ex.target]
end
#=> ["customer.purge", "ur9ytargets"]

## the raised error names the verb and target, and never the detail contents
begin
  ColonelAuditEvent.record(
    actor: 'a', verb: 'organization.delete', target: 'on_orgext1', result: :success,
    detail: Boom.new, fail_closed: true,
  )
rescue Onetime::AuditWriteFailure => ex
  [ex.message.include?('organization.delete'), ex.message.include?('on_orgext1'), ex.message.include?('boom')]
end
#=> [true, true, false]

## it is NOT an authorization rejection: AuditedFailure must not drop it
require 'onetime/audited_failure'
err = Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 't')
[err.is_a?(Onetime::Forbidden), err.is_a?(Onetime::Unauthorized),
 Onetime::AuditedFailure.authorization_rejection?(err)]
#=> [false, false, false]

## a fail-closed failure still leaves the set untouched (nothing half-written)
ColonelAuditEvent.count
#=> 0

## fail_closed: true on a HEALTHY write behaves exactly like the default
@ok = ColonelAuditEvent.record(
  actor: 'a', verb: 'customer.purge', target: 't', result: :success, fail_closed: true,
)
[@ok['verb'], ColonelAuditEvent.count]
#=> ["customer.purge", 1]

## record_security has NO fail_closed mode: unauthenticated writers get no
## abort primitive, so the same failure still returns nil
ColonelAuditEvent.events.clear
ColonelAuditEvent.record_security(actor: 'anonymous', verb: 'v', target: 't', result: :failure, detail: Boom.new)
#=> nil

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

## -- Retention narrows only via the constants (#4334) --------------------
#
# trim! is public, and its `cap` argument used to be taken at face value —
# `trim!(0)` emptied the entire operator trail in one call. It is now clamped
# UP to MAX_EVENTS, so retention can only ever widen through this API.
# (Eviction mechanics under a lowered cap are covered in the rspec sibling,
# which can stub_const MAX_EVENTS; tryouts cannot.)

## trim!(0) no longer wipes the trail
ColonelAuditEvent.events.clear
5.times { |i| ColonelAuditEvent.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }
[ColonelAuditEvent.trim!(0), ColonelAuditEvent.count]
#=> [0, 5]

## any cap below MAX_EVENTS is clamped, negatives included
[ColonelAuditEvent.trim!(1), ColonelAuditEvent.trim!(-100), ColonelAuditEvent.count]
#=> [0, 0, 5]

## the trail is intact and still newest-first after the clamped calls
ColonelAuditEvent.recent(3).map { |e| e['verb'] }
#=> ["v4", "v3", "v2"]

## trim! at the real cap is a no-op when the set is under it
ColonelAuditEvent.trim!(ColonelAuditEvent::MAX_EVENTS)
#=> 0

## trim_security! clamps its cap the same way
ColonelAuditEvent.security_events.clear
3.times { |i| ColonelAuditEvent.record_security(actor: 'anonymous', verb: "s#{i}", target: 't', result: :failure) }
[ColonelAuditEvent.trim_security!(0), ColonelAuditEvent.security_count]
#=> [0, 3]

## trim_security! also clamps the AGE bound: the second door into the same wipe
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.security_events.add({ 'verb' => 'older' }, Familia.now - 3600)
ColonelAuditEvent.security_events.add({ 'verb' => 'newer' }, Familia.now)
[ColonelAuditEvent.trim_security!(ColonelAuditEvent::MAX_SECURITY_EVENTS, 1), ColonelAuditEvent.security_count]
#=> [0, 2]

## a non-positive max_age still disables the age pass (it keeps MORE, not less)
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.security_events.add({ 'verb' => 'ancient' }, Familia.now - 100_000_000)
[ColonelAuditEvent.trim_security!(ColonelAuditEvent::MAX_SECURITY_EVENTS, 0), ColonelAuditEvent.security_count]
#=> [0, 1]

## -- The external sink (#4334) -------------------------------------------
#
# Every event is emitted as a structured log line BEFORE the datastore write,
# on a dedicated SemanticLogger category, so a datastore outage cannot lose the
# record. The sink is the durability story; the sorted sets are the cache.

## the sink logger is the dedicated ColonelAudit category
ColonelAuditEvent.sink_logger.name
#=> "ColonelAudit"

## its level is PINNED in code, not inherited from the app default level
ColonelAuditEvent.sink_logger.level
#=> :info

## a record emits exactly one sink line, carrying the trail it landed in
# Swap the memoized handle for a recorder rather than patching the real logger
# or reading appender output: what matters is what the write path emits.
class SinkSpy
  attr_reader :lines

  def initialize
    @lines = []
  end

  def info(message, payload = nil)
    @lines << [message, payload]
  end
end
ColonelAuditEvent.events.clear
@spy = SinkSpy.new
ColonelAuditEvent.instance_variable_set(:@sink_logger, @spy)
ColonelAuditEvent.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_v', result: :success)
[@spy.lines.size, @spy.lines.first[0], @spy.lines.first[1]['verb'], @spy.lines.first[1]['trail']]
#=> [1, "colonel.audit", "customer.purge", "events"]

## security telemetry is shipped too, tagged with the other trail
ColonelAuditEvent.record_security(actor: 'anonymous', verb: 'auth.throttled', target: 'ip', result: :failure)
[@spy.lines.size, @spy.lines.last[1]['trail']]
#=> [2, "security_events"]

## and so are observations — every trail ships, the split only budgets Redis
ColonelAuditEvent.record_access(actor: 'ur_col', verb: 'audit.list', target: 'colonel_audit', result: :success)
[@spy.lines.size, @spy.lines.last[1]['verb'], @spy.lines.last[1]['trail']]
#=> [3, "audit.list", "access_events"]

## the sink receives the REDACTED detail, never the caller's original
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: { 'passphrase' => 'hunter2' })
@spy.lines.last[1]['detail']
#=> { "passphrase" => "[REDACTED]" }

## a sink failure never costs the trail its datastore copy
ColonelAuditEvent.events.clear
def @spy.info(*) = raise('appender exploded')
@ev2 = ColonelAuditEvent.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)
[@ev2['verb'], ColonelAuditEvent.count]
#=> ["customer.purge", 1]

# Restore the real sink handle for the remaining cases.
ColonelAuditEvent.remove_instance_variable(:@sink_logger)
ColonelAuditEvent.events.clear

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

## flooding the security trail evicts NOTHING from the operator trail — the
## whole point of the split (the caps are separate budgets, not one)
ColonelAuditEvent.security_events.clear
5.times { |i| ColonelAuditEvent.record_security(actor: 'anonymous', verb: "s#{i}", target: 't', result: :failure) }
[ColonelAuditEvent.security_count, ColonelAuditEvent.count]
#=> [5, 1]

## security reads are newest-first, like the operator trail
ColonelAuditEvent.recent_security(3).map { |e| e['verb'] }
#=> ["s4", "s3", "s2"]

## the security trail also has an AGE bound (the operator trail has none):
## members older than SECURITY_EVENT_RETENTION are removed by score
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.security_events.add({ 'verb' => 'stale' }, Familia.now - ColonelAuditEvent::SECURITY_EVENT_RETENTION - 100)
ColonelAuditEvent.security_events.add({ 'verb' => 'fresh' }, Familia.now)
removed = ColonelAuditEvent.trim_security!(ColonelAuditEvent::MAX_SECURITY_EVENTS, ColonelAuditEvent::SECURITY_EVENT_RETENTION)
[removed, ColonelAuditEvent.recent_security(5).map { |e| e['verb'] }]
#=> [1, ["fresh"]]

## a max_age LONGER than the retention window is honoured — widening is the
## one direction the clamp allows
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.security_events.add({ 'verb' => 'aged' }, Familia.now - ColonelAuditEvent::SECURITY_EVENT_RETENTION - 100)
[ColonelAuditEvent.trim_security!(ColonelAuditEvent::MAX_SECURITY_EVENTS, ColonelAuditEvent::SECURITY_EVENT_RETENTION * 2),
 ColonelAuditEvent.security_count]
#=> [0, 1]

## recent_security(0) returns an empty array
ColonelAuditEvent.recent_security(0)
#=> []

## -- Observation trail: a THIRD retention domain (#4335) -------------------
#
# Same eviction-boundary reasoning as the security trail, applied to a
# different risk: these writers are authenticated and trusted, but chatty by
# construction (curated sensitive reads, dry-run previews), so an operator
# working one incident must not be able to page the mutation trail out of
# existence just by browsing.

## access_events is a distinct backing set — not the operator trail, not security
ColonelAuditEvent.access_events.dbkey
#=> "colonel_audit_event:access_events"

## record_access stores the same event shape as the other two write paths
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.access_events.clear
@acc = ColonelAuditEvent.record_access(
  actor: 'ur_col', verb: 'secret.receipt_view', target: 'sh_abc', result: :success,
  detail: { 'state' => 'received' },
)
[@acc['actor'], @acc['verb'], @acc['result'], @acc['detail']]
#=> ["ur_col", "secret.receipt_view", "success", { "state" => "received" }]

## an observation NEVER lands in the operator trail — the eviction boundary
[ColonelAuditEvent.count, ColonelAuditEvent.security_count, ColonelAuditEvent.access_count]
#=> [0, 0, 1]

## conversely, an operator write never lands in the observation trail
ColonelAuditEvent.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_v', result: :success)
[ColonelAuditEvent.count, ColonelAuditEvent.access_count]
#=> [1, 1]

## flooding the observation trail evicts NOTHING from the operator trail — the
## whole point of the third budget
ColonelAuditEvent.access_events.clear
5.times { |i| ColonelAuditEvent.record_access(actor: 'ur_col', verb: "read#{i}", target: 't', result: :success) }
[ColonelAuditEvent.access_count, ColonelAuditEvent.count]
#=> [5, 1]

## observation reads are newest-first, like the other two trails
ColonelAuditEvent.recent_access(3).map { |e| e['verb'] }
#=> ["read4", "read3", "read2"]

## recent_access(0) returns an empty array
ColonelAuditEvent.recent_access(0)
#=> []

## the observation budget is its own, and smaller than the operator trail's:
## "who looked" is supporting context for "who changed"
[ColonelAuditEvent::MAX_ACCESS_EVENTS < ColonelAuditEvent::MAX_EVENTS,
 ColonelAuditEvent::ACCESS_EVENT_RETENTION > ColonelAuditEvent::SECURITY_EVENT_RETENTION]
#=> [true, true]

## record_access has NO fail_closed mode: observing must never break the console
class BoomAccess
  def to_s = raise('detail exploded')
end
ColonelAuditEvent.record_access(actor: 'ur_col', verb: 'v', target: 't', result: :success,
                                detail: BoomAccess.new)
#=> nil

## trim_access! clamps its cap in the widening direction, like the other trails
ColonelAuditEvent.access_events.clear
3.times { |i| ColonelAuditEvent.record_access(actor: 'ur_col', verb: "a#{i}", target: 't', result: :success) }
[ColonelAuditEvent.trim_access!(0), ColonelAuditEvent.access_count]
#=> [0, 3]

## trim_access! clamps the AGE bound too — the second door into the same wipe
ColonelAuditEvent.access_events.clear
ColonelAuditEvent.access_events.add({ 'verb' => 'older' }, Familia.now - 3600)
ColonelAuditEvent.access_events.add({ 'verb' => 'newer' }, Familia.now)
[ColonelAuditEvent.trim_access!(ColonelAuditEvent::MAX_ACCESS_EVENTS, 1), ColonelAuditEvent.access_count]
#=> [0, 2]

## a non-positive max_age disables the age pass entirely, which keeps MORE
ColonelAuditEvent.access_events.clear
ColonelAuditEvent.access_events.add({ 'verb' => 'ancient' }, Familia.now - 100_000_000)
[ColonelAuditEvent.trim_access!(ColonelAuditEvent::MAX_ACCESS_EVENTS, 0), ColonelAuditEvent.access_count]
#=> [0, 1]

## members older than ACCESS_EVENT_RETENTION are removed by score
ColonelAuditEvent.access_events.clear
ColonelAuditEvent.access_events.add({ 'verb' => 'stale' }, Familia.now - ColonelAuditEvent::ACCESS_EVENT_RETENTION - 100)
ColonelAuditEvent.access_events.add({ 'verb' => 'fresh' }, Familia.now)
@removed_access = ColonelAuditEvent.trim_access!(ColonelAuditEvent::MAX_ACCESS_EVENTS,
                                                 ColonelAuditEvent::ACCESS_EVENT_RETENTION)
[@removed_access, ColonelAuditEvent.recent_access(5).map { |e| e['verb'] }]
#=> [1, ["fresh"]]

# Cleanup
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.access_events.clear
