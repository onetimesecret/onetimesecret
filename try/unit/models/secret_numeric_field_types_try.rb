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
# the numeric fields at the serialization boundary. lifespan/secret_ttl use
# to_i (lossless integer-second durations, nil/-1 preserved for unset);
# created/updated use to_f, NOT to_i, to keep the sub-second precision that
# matters when those values are used as sorted-set scores. Hydration is
# intentionally untouched -- getters still return whatever type is at rest
# (parts 3 and 4 below pin that) -- but the wire format is numeric even for
# poisoned records, so the V3 schema passes either way. A read-only detector
# for finding already-poisoned records at rest lives in
# scripts/diagnostics/detect_string_typed_numerics.rb (part 6 below).
#
# The companion frontend test (string-typed lifespan/created rejected by
# the V3 schema) lives in:
#   src/tests/stores/secrets/secretStoreFieldHandling.spec.ts
#
# See also: try/unit/models/customer_field_serialization_try.rb (#3016),
# the mirror-image bug where writers bypassed JSON serialization.

require_relative '../../support/test_models'
require_relative '../../../scripts/diagnostics/detect_string_typed_numerics'

OT.boot! :test, true

@redis = Familia.dbclient
@detector = Diagnostics::DetectStringTypedNumerics
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

## safe_dump emits native numeric types for all four V3 z.number() fields:
## integer-second durations and float epoch-second timestamps (to_f keeps
## the float; truncating would reorder sorted-set range queries)
sd = Onetime::Secret.load(@secret.objid).safe_dump
[sd[:lifespan].class, sd[:secret_ttl].class, sd[:created].class, sd[:updated].class]
#=> [Integer, Integer, Float, Float]

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
#=> ['previewed', Integer, Float]

## Receipt safe_dump numeric fields are natively typed too
## (lifespan, secret_ttl, metadata_ttl, receipt_ttl, created, updated)
sd = Onetime::Receipt.load(@receipt.objid).safe_dump
[sd[:lifespan].class, sd[:secret_ttl].class, sd[:metadata_ttl].class,
 sd[:receipt_ttl].class, sd[:created].class, sd[:updated].class,]
#=> [Integer, Integer, Integer, Integer, Float, Float]

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

## The boundary cast recovers native numbers from the poisoned record, so
## the V3 payload carries numbers despite the Strings underneath. lifespan/
## secret_ttl come back Integer (to_i); created/updated come back Float
## (to_f), preserving the stored sub-second value
sd = Onetime::Secret.load(@secret.objid).safe_dump
[sd[:lifespan], sd[:secret_ttl], sd[:created], sd[:updated]]
#=> [604800, 604800, 1735142814.123456, 1735204014.0]

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

## An unset lifespan stays nil on the wire (not 0). The V3 secret/receipt
## contracts declare secret_ttl/lifespan z.number().nullable() so this null
## parses (the null half of #3424); see
## src/tests/contracts/v3-schema-null-safety.spec.ts
unsaved = Onetime::Secret.new(owner_id: 'anon')
unsaved.safe_dump[:lifespan]
#=> nil

## Degenerate case: a JSON-quoted empty string at rest ('""', a writer
## assigned a Ruby "") hydrates as "" and dumps as 0.0. Deliberate:
## created/updated are NON-nullable z.number() in the V3 secret and
## receipt shapes, so emitting nil here would fail gracefulParse and make
## the record unreachable again -- a wrong-but-parseable epoch-0 keeps it
## viewable. The detector flags these records (see part 6).
@redis.hset(@sticky.dbkey, 'created', '""')
loaded = Onetime::Secret.load(@sticky.objid)
[loaded.created, loaded.safe_dump[:created]]
#=> ['', 0.0]

## Truly empty bytes at rest ('') are a different case: Familia's
## deserialize_value treats them as unset and hydrates nil, so the
## nil-safe cast dumps nil, never 0.0
@redis.hset(@sticky.dbkey, 'created', '')
loaded = Onetime::Secret.load(@sticky.objid)
[loaded.created, loaded.safe_dump[:created]]
#=> [nil, nil]

# ------------------------------------------------------------------
# 6. Detector. The boundary cast fixes the wire but leaves the at-rest
#    bytes corrupt, so scripts/diagnostics/detect_string_typed_numerics.rb
#    scans for records that need fixing (and helps locate the writer).
#    It flags JSON strings where the schema wants JSON numbers -- the
#    mirror image of #3016's detector, which flags non-JSON bytes. These
#    pin the predicate so the scan can be trusted.
# ------------------------------------------------------------------

## A JSON-quoted numeric string (the #3424 poison) is detected
@detector.string_typed_numeric?('"604800"')
#=> true

## A bare JSON number is healthy (parses to Integer, not String)
@detector.string_typed_numeric?('604800')
#=> false

## A bare JSON float is healthy (parses to Float)
@detector.string_typed_numeric?('1735142814.123456')
#=> false

## nil and empty (unset field) are not flagged
[@detector.string_typed_numeric?(nil), @detector.string_typed_numeric?('')]
#=> [false, false]

## A JSON-quoted EMPTY string at rest IS flagged: the raw bytes '""' are
## not empty, and they parse to a Ruby String -- so the degenerate
## records from part 5 do surface in a scan
@detector.string_typed_numeric?('""')
#=> true

## A bare non-JSON string is NOT this bug -- that is #3016's detector
@detector.string_typed_numeric?('anon')
#=> false

## poisoned_fields returns only the string-typed numeric fields from a hash
fields = { 'lifespan' => '"604800"', 'created' => '1781282977.7', 'updated' => '"1781282977"' }
@detector.poisoned_fields(fields, %w[lifespan created updated]).sort
#=> ['lifespan', 'updated']

## End-to-end: a poisoned record's real hgetall is flagged by the detector
raw = @redis.hgetall(@poisoned.dbkey)
@detector.poisoned_fields(raw, %w[lifespan created updated]).include?('lifespan')
#=> true

## ...and a healthy record's hgetall is clean
@receipt3, @secret3 = Onetime::Receipt.spawn_pair('anon', 3600, 'detector control')
raw = @redis.hgetall(@secret3.dbkey)
@detector.poisoned_fields(raw, %w[lifespan created updated])
#=> []

# TEARDOWN

@secret.delete!
@receipt.delete!
@secret2.delete!
@receipt2.delete!
@secret3.delete!
@receipt3.delete!
@poisoned.delete!
@sticky.delete!
