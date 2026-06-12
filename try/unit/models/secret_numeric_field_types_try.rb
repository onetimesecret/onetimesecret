# try/unit/models/secret_numeric_field_types_try.rb
#
# frozen_string_literal: true

# Reproduction + mechanism isolation for issue #3424 (follow-up to #3268):
# "Secrets immediately show 'no longer available' / marked previewed, never
# viewable (V3 schema numeric type mismatch)".
#
# Reported symptom: GET /api/v3/guest/secret/:identifier returns 200, but
# `lifespan`, `secret_ttl`, `created` and `updated` arrive as JSON strings
# ("604800") instead of numbers (604800). The V3 Zod schema declares these
# fields z.number() (strict, no coercion), so gracefulParse throws, the
# record stays null, and the recipient sees UnknownSecret even though the
# secret was never consumed.
#
# These tests isolate the exact mechanism by checking types at every
# boundary against a real database: at-rest bytes -> hydrated getters ->
# safe_dump -> rendered JSON. Three findings:
#
# 1. The default write path is fully typed. spawn_pair stores lifespan as a
#    bare JSON integer and created/updated as bare JSON floats (Familia.now
#    is Float). Hydration parses them back to Integer/Float, and safe_dump
#    emits native numbers. This is why the bug does not reproduce in a
#    clean environment (delano's result on #3268).
#
# 2. Bare numeric bytes at rest are NOT the mechanism. Familia v2's
#    deserializer (Oj :strict) parses unquoted bytes like "604800" or
#    "1735142814.123456" to Integer/Float. So v1-era raw values, and the
#    hypothesis that "floats stored as strings don't hydrate back as
#    floats", are both ruled out.
#
# 3. The ONLY at-rest state that reproduces the reported payload is a
#    JSON-QUOTED numeric string ('"604800"', quote bytes included). Familia
#    v2's serializer is type-preserving by contract: serialize_value JSON-
#    encodes whatever Ruby type the application assigned. Assign a String
#    (an unconverted form param, config value, console fix, or any code
#    path that calls hset with a quoted value) and the record is poisoned:
#    it hydrates as String on every subsequent load. The recipient flow
#    never heals it: previewed! uses save_fields(:state), which rewrites
#    only the state field.
#
# MITIGATION (#3424): the safe_dump lambdas in Secret and Receipt now cast
# the numeric fields at the serialization boundary (lifespan/secret_ttl
# via to_i with nil/-1 preserved for unset, created/updated via &.to_i).
# Hydration is intentionally untouched -- getters still return whatever
# type is at rest (parts 3 and 4 below pin that) -- but the wire format is
# numeric even for poisoned records, so the V3 schema passes either way.
#
# The companion frontend test (string-typed lifespan/created rejected by
# the V3 schema) lives in:
#   src/tests/stores/secrets/secretStoreFieldHandling.spec.ts
#
# See also: try/unit/models/customer_field_serialization_try.rb (#3016),
# the mirror-image bug where writers bypassed JSON serialization.

require_relative '../../support/test_models'

OT.boot! :test, true

@redis = Familia.dbclient
@lifespan = 604_800
@receipt, @secret = Onetime::Receipt.spawn_pair('anon', @lifespan, 'numeric type fidelity probe')
@secret_key = @secret.dbkey

# ------------------------------------------------------------------
# 1. Healthy write path: spawn_pair -> at-rest bytes -> load ->
#    safe_dump. Everything is natively typed. This codifies why the
#    bug does NOT reproduce in a clean environment.
# ------------------------------------------------------------------

## At rest, lifespan is stored as a bare JSON integer (no quote bytes)
@redis.hget(@secret_key, 'lifespan')
#=> '604800'

## At rest, created is a bare JSON float: Familia.now (Float seconds),
## written by prepare_for_save, serialized without quotes
raw = @redis.hget(@secret_key, 'created')
[raw.start_with?('"'), raw.match?(/\A\d+\.\d+\z/)]
#=> [false, true]

## A fresh load hydrates lifespan back as Integer
Onetime::Secret.load(@secret.objid).lifespan
#=> 604800

## A fresh load hydrates created/updated back as Float
loaded = Onetime::Secret.load(@secret.objid)
[loaded.created.class, loaded.updated.class]
#=> [Float, Float]

## safe_dump emits native numeric types for all four V3 z.number() fields
## (the boundary cast truncates float timestamps to whole epoch seconds)
sd = Onetime::Secret.load(@secret.objid).safe_dump
[sd[:lifespan].class, sd[:secret_ttl].class, sd[:created].class, sd[:updated].class]
#=> [Integer, Integer, Integer, Integer]

## The rendered JSON carries unquoted numbers -- this payload passes the
## V3 schema (lifespan: z.number(), secret_ttl: z.number())
sd = Onetime::Secret.load(@secret.objid).safe_dump
Familia::JsonSerializer.dump(lifespan: sd[:lifespan], secret_ttl: sd[:secret_ttl])
#=> '{"lifespan":604800,"secret_ttl":604800}'

## previewed! (the exact ShowSecret flow the recipient triggers) only
## rewrites state via save_fields(:state); numeric fields keep their types
fresh = Onetime::Secret.load(@secret.objid)
fresh.previewed!
sd = Onetime::Secret.load(@secret.objid).safe_dump
[sd[:state], sd[:lifespan].class, sd[:created].class]
#=> ['previewed', Integer, Integer]

## Receipt safe_dump numeric fields are natively typed too
## (lifespan, secret_ttl, metadata_ttl, receipt_ttl, created, updated)
sd = Onetime::Receipt.load(@receipt.objid).safe_dump
[sd[:lifespan].class, sd[:secret_ttl].class, sd[:metadata_ttl].class,
 sd[:receipt_ttl].class, sd[:created].class, sd[:updated].class,]
#=> [Integer, Integer, Integer, Integer, Integer, Integer]

# ------------------------------------------------------------------
# 2. Ruling out bare bytes at rest (v1-era raw values, and the
#    "floats stored as strings don't hydrate as floats" hypothesis
#    from the issue thread). Oj :strict parses bare numeric bytes
#    to native numbers, so these are NOT the mechanism.
# ------------------------------------------------------------------

## Bare integer bytes (v1-style raw hset, no JSON quotes) hydrate as Integer
@redis.hset(@secret_key, 'lifespan', '86400')
Onetime::Secret.load(@secret.objid).lifespan
#=> 86400

## Bare float bytes hydrate as Float -- a float stored as an unquoted
## string DOES come back as a Float
@redis.hset(@secret_key, 'created', '1735142814.123456')
loaded = Onetime::Secret.load(@secret.objid)
[loaded.created.class, loaded.created]
#=> [Float, 1735142814.123456]

# ------------------------------------------------------------------
# 3. THE REPRODUCTION. JSON-quoted numeric strings at rest are the
#    only state that produces the #3424 payload: deserialize_value
#    faithfully returns a Ruby String. Before the boundary cast,
#    safe_dump passed that String straight to the wire
#    ('{"lifespan":"604800"}'), which strict z.number() rejects --
#    gracefulParse threw, record stayed null, and the recipient saw
#    UnknownSecret ("That information is no longer available"). The
#    cast now neutralizes the poison at serialization time.
# ------------------------------------------------------------------

## JSON-quoted numeric bytes (quote bytes included) hydrate as String --
## the poisoned state. Hydration is intentionally not coerced; only the
## safe_dump boundary is.
@redis.hset(@secret_key, 'lifespan', '"604800"')
@redis.hset(@secret_key, 'created', '"1735142814.123456"')
@redis.hset(@secret_key, 'updated', '"1735204014"')
loaded = Onetime::Secret.load(@secret.objid)
[loaded.lifespan.class, loaded.created.class, loaded.updated.class]
#=> [String, String, String]

## The boundary cast recovers native Integers from the poisoned record,
## so the V3 payload carries numbers despite the Strings underneath
sd = Onetime::Secret.load(@secret.objid).safe_dump
[sd[:lifespan], sd[:secret_ttl], sd[:created], sd[:updated]]
#=> [604800, 604800, 1735142814, 1735204014]

## The rendered JSON is unquoted -- this payload passes the strict
## z.number() fields of the V3 schema even for a poisoned record
sd = Onetime::Secret.load(@secret.objid).safe_dump
Familia::JsonSerializer.dump(lifespan: sd[:lifespan], secret_ttl: sd[:secret_ttl])
#=> '{"lifespan":604800,"secret_ttl":604800}'

# ------------------------------------------------------------------
# 4. The writer mechanism: how an environment gets into that state.
#    Familia v2's contract is "the type you save is the type you get
#    back". JSON field serialization preserves application types; it
#    does not normalize numeric strings. One stringly-typed writer
#    poisons the record permanently.
# ------------------------------------------------------------------

## Assigning a String lifespan (an unconverted param/config value)
## stores JSON-quoted bytes -- the poisoned at-rest state from part 3
@poisoned = Onetime::Secret.new(owner_id: 'anon')
@poisoned.lifespan = '604800'
@poisoned.save
@redis.hget(@poisoned.dbkey, 'lifespan')
#=> '"604800"'

## ...and that record hydrates as String on every load thereafter
Onetime::Secret.load(@poisoned.objid).lifespan.class
#=> String

## Diagnostic signature of a poisoned record: a full save() heals
## `updated` (prepare_for_save always overwrites it with Familia.now)
## but never `created` (set with ||=) and never `lifespan`
@sticky = Onetime::Secret.new(owner_id: 'anon')
@sticky.lifespan = '604800'
@sticky.created  = '1735142814'
@sticky.save
loaded = Onetime::Secret.load(@sticky.objid)
[loaded.created.class, loaded.updated.class, loaded.lifespan.class]
#=> [String, Float, String]

## The recipient flow cannot heal a poisoned record either: previewed!
## writes only the state field. The String survives at rest -- but the
## boundary cast keeps the V3 payload numeric regardless
poisoned = Onetime::Secret.load(@poisoned.objid)
poisoned.previewed!
reloaded = Onetime::Secret.load(@poisoned.objid)
[reloaded.lifespan.class, reloaded.safe_dump[:lifespan]]
#=> [String, 604800]

# ------------------------------------------------------------------
# 5. Cast semantics pinned at the getter level. The safe_dump lambdas
#    in secret/features/safe_dump_fields.rb (and the receipt mirror)
#    rely on to_i recovering Integers from poisoned Strings while
#    being a no-op for healthy values, with nil preserved for unset
#    lifespans. These cases pin that contract.
# ------------------------------------------------------------------

## to_i recovers native Integers from a poisoned record's String fields
loaded = Onetime::Secret.load(@poisoned.objid)
[loaded.lifespan.to_i, loaded.lifespan.to_i > 0 ? loaded.lifespan.to_i : nil]
#=> [604800, 604800]

## ...and is a no-op for a healthy record's native values
@receipt2, @secret2 = Onetime::Receipt.spawn_pair('anon', 3600, 'healthy control')
value = Onetime::Secret.load(@secret2.objid).lifespan
[value, value.to_i]
#=> [3600, 3600]

## An unset lifespan stays nil on the wire (not 0): the V3 null-rejection
## path for legacy records is unchanged by the cast
unsaved = Onetime::Secret.new(owner_id: 'anon')
unsaved.safe_dump[:lifespan]
#=> nil

# TEARDOWN

@secret.delete!
@receipt.delete!
@secret2.delete!
@receipt2.delete!
@poisoned.delete!
@sticky.delete!
