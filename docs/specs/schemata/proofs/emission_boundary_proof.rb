# docs/specs/schemata/proofs/emission_boundary_proof.rb
#
# frozen_string_literal: true

# rubocop:disable Style/GlobalVars
#
# Executable evidence for docs/specs/schemata/schema-target-architecture.md.
#
# Claims proven, using only the gems already pinned in Gemfile.lock
# (json_schemer 2.5.0, familia 2.11.2) and the JSON Schemas already
# generated from the Zod registry (generated/schemas/shapes/*):
#
#   P1. Wire validation at the emission boundary catches every member of
#       the #3424 failure class — legacy enum state, string-typed numerics,
#       null-typed required numerics — naming the failing field precisely.
#   P2. The unit of wire validation must be the FINAL endpoint payload,
#       not raw safe_dump output: a faithful bare-safe_dump record FAILS
#       the shape schema on the merged-in fields (natural_expiration,
#       expiration_in_seconds, share/burn/receipt paths and urls). This is
#       the empirical form of the review round's Phase-2 correction, now
#       folded into the cure spec (schema-source-of-truth.md).
#   P3. Deprecated aliases (viewed/received/is_viewed/is_received) pass as
#       additionalProperties — the V3 *wire* carries them today even though
#       the V3 shape excludes them; tightening is a policy knob, not a
#       precondition.
#   P4. Familia::SchemaRegistry supports this today via explicit name keys
#       (multiple schemas per class: storage vs wire) — no upstream change
#       needed for the MVP.
#   P5. Familia's default JsonSchemerValidator compiles the schema on every
#       call — asserted from the gem source, not a stopwatch (timing
#       assertions flake). The relative cost is printed informationally,
#       and a memoizing validator injected via Familia.schema_validator is
#       shown to work.
#   P6 (informational, not asserted). Discipline-based alignment fails in
#       practice: when this proof was written (2026-07-06) the hand-kept TS
#       mirror of the Ruby safe_dump field list
#       (src/tests/contracts/receipt-safe-dump-fields.ts, "Update this list
#       when safe_dump_fields.rb changes") was stale — missing
#       recipient_name and source. The script reports the current drift
#       status without asserting it, so it keeps passing once the mirror is
#       synced or deleted; the durable gate has inverted polarity (fail
#       WHEN drifted) and belongs in CI.
#
# Run: bundle exec ruby docs/specs/schemata/proofs/emission_boundary_proof.rb
# No Redis/Valkey, no OT.boot!, no network. Exits non-zero on any
# expectation failure.

require 'bundler/setup'
require 'json'
require 'json_schemer'
require 'benchmark'
require 'familia'

ROOT       = File.expand_path('../../../..', __dir__)
SHAPE_PATH = File.join(ROOT, 'generated/schemas/shapes/receipt.schema.json')

$failures = []
$checks   = 0

def check(label, actual, expected: true)
  $checks += 1
  ok       = (actual == expected)
  puts format('  %s %s', ok ? 'PASS' : 'FAIL', label)
  $failures << label unless ok
  ok
end

def error_pointers(schema, data)
  JSONSchemer.schema(schema).validate(data).map { |e| e['data_pointer'] }.uniq
end

schema = JSON.parse(File.read(SHAPE_PATH))

# ---------------------------------------------------------------------------
# Fixture: a faithful V3 single-receipt endpoint payload — safe_dump output
# merged with the logic-class computed attributes, exactly the record the
# SPA's gracefulParse(responseSchemas.receipt, ...) receives.
# ---------------------------------------------------------------------------
now     = 1_780_000_000.0
healthy = {
  # safe_dump projection
  'identifier' => 'rcpt0abc123def456',
  'key' => 'rcpt0abc123def456',
  'shortid' => 'rcpt0abc',
  'state' => 'new',
  'custid' => 'cust_01',
  'owner_id' => 'cust_01',
  'created' => now,
  'updated' => now,
  'shared' => nil,
  'previewed' => nil,
  'revealed' => nil,
  'burned' => nil,
  'secret_ttl' => 604_800,
  'receipt_ttl' => 1_209_600,
  'lifespan' => 1_209_600,
  'secret_shortid' => 'scrt0abc',
  'secret_identifier' => 'scrt0abc123def456',
  'recipients' => '',
  'recipient_name' => nil,
  'share_domain' => nil,
  'has_passphrase' => false,
  'is_previewed' => false,
  'is_revealed' => false,
  'is_burned' => false,
  'is_destroyed' => false,
  'is_expired' => false,
  'is_orphaned' => false,
  'memo' => nil,
  'kind' => 'conceal',
  'source' => 'standard',
  # logic-class merge (_receipt_attributes): the implicit second shape
  'secret_state' => 'new',
  'natural_expiration' => '7 days',
  'expiration' => now + 604_800,
  'expiration_in_seconds' => 604_800,
  'share_path' => '/secret/scrt0abc123def456',
  'burn_path' => '/receipt/rcpt0abc123def456/burn',
  'receipt_path' => '/receipt/rcpt0abc123def456',
  'share_url' => 'https://example.com/secret/scrt0abc123def456',
  'receipt_url' => 'https://example.com/receipt/rcpt0abc123def456',
  'burn_url' => 'https://example.com/receipt/rcpt0abc123def456/burn',
}

puts "\nP1. Emission-boundary validation catches the #3424 class"
check 'healthy merged payload validates', error_pointers(schema, healthy).empty?

legacy_state = healthy.merge('state' => 'viewed') # pre-rename stored value
check 'legacy state "viewed" rejected at /state',
  error_pointers(schema, legacy_state),
  expected: ['/state']

poisoned_ttl = healthy.merge('secret_ttl' => '604800') # string-typed numeric
check 'string-typed secret_ttl rejected at /secret_ttl',
  error_pointers(schema, poisoned_ttl),
  expected: ['/secret_ttl']

null_created = healthy.merge('created' => nil) # nil where contract is strict
check 'null created rejected at /created',
  error_pointers(schema, null_created),
  expected: ['/created']

legacy_secret_state = healthy.merge('secret_state' => 'received')
check 'legacy secret_state "received" (merge-path field) rejected at /secret_state',
  error_pointers(schema, legacy_secret_state),
  expected: ['/secret_state']

puts "\nP2. Raw safe_dump output is NOT the unit of validation"
merge_fields          = %w[secret_state natural_expiration expiration expiration_in_seconds
                           share_path burn_path receipt_path share_url receipt_url burn_url]
bare_safe_dump        = healthy.except(*merge_fields)
required_errors       = JSONSchemer.schema(schema).validate(bare_safe_dump).to_a
missing_keys          = required_errors.flat_map { |e| e.dig('details', 'missing_keys') || [] }.sort
required_merge_fields = (schema['required'] & merge_fields).sort # secret_state is nullish, not required
check 'bare safe_dump record fails the shape schema (merged fields required)',
  missing_keys,
  expected: required_merge_fields
puts "       (missing required merged-in fields: #{missing_keys.join(', ')})"

puts "\nP3. Deprecated aliases pass as additionalProperties"
with_aliases = healthy.merge(
  'viewed' => nil,
  'received' => nil,
  'is_viewed' => false,
  'is_received' => false,
  'metadata_ttl' => 1_209_600,
)
check 'payload carrying viewed/received/is_viewed/is_received still validates',
  error_pointers(schema, with_aliases).empty?

puts "\nP4. Familia::SchemaRegistry supports named wire schemas as-is"
Familia::SchemaRegistry.reset!
Familia.schemas          = { 'Onetime::Receipt.wire.v3' => SHAPE_PATH }
result                   = Familia::SchemaRegistry.validate('Onetime::Receipt.wire.v3', healthy)
check 'registry validates healthy payload under a wire-specific key', result[:valid]
result                   = Familia::SchemaRegistry.validate('Onetime::Receipt.wire.v3', legacy_state)
check 'registry rejects legacy state under the same key', result[:valid], expected: false
check 'registry error names the field',
  result[:errors].first['data_pointer'],
  expected: '/state'

puts "\nP5. Default validator recompiles per call; a cached one must be injected"
# The durable claim is provable from the gem source without a stopwatch:
# JsonSchemerValidator#validate constructs a fresh JSONSchemer schema inside
# the method body, so every call pays compilation.
src_file, src_line = Familia::JsonSchemerValidator.instance_method(:validate).source_location
method_body        = File.readlines(src_file)[src_line - 1, 4].join
check 'gem source: JsonSchemerValidator#validate compiles the schema per call',
  method_body.include?('JSONSchemer.schema(')

compiled  = JSONSchemer.schema(schema)
n         = 200
recompile = Benchmark.realtime { n.times { JSONSchemer.schema(schema).valid?(healthy) } }
cached    = Benchmark.realtime { n.times { compiled.valid?(healthy) } }
puts format(
  '       informational: %d validations — recompile-per-call: %.1fms, cached: %.1fms (%.1fx)',
  n,
  recompile * 1000,
  cached * 1000,
  recompile / cached,
)

# A caching validator is injectable without touching the gem:
class CachedSchemerValidator
  def initialize = @cache = {}

  def validate(schema, data)
    (@cache[schema.object_id] ||= JSONSchemer.schema(schema)).validate(data) # rubocop:disable Lint/HashCompareByIdentity
  end
end
Familia::SchemaRegistry.reset!
Familia.schemas          = { 'Onetime::Receipt.wire.v3' => SHAPE_PATH }
Familia.schema_validator = CachedSchemerValidator.new
result                   = Familia::SchemaRegistry.validate('Onetime::Receipt.wire.v3', healthy)
check 'custom cached validator injects cleanly via Familia.schema_validator', result[:valid]
Familia.schema_validator = :json_schemer # restore default

puts "\nP6. Drift status of the hand-maintained TS mirror (informational)"
# Evidence-of-the-moment, deliberately NOT asserted: this script must keep
# passing after the mirror is synced or deleted. The durable gate has
# inverted polarity — fail WHEN drifted — and belongs in CI, not in a proof.
# Stale when this proof was written (2026-07-06): missing recipient_name, source.
mirror_path = File.join(ROOT, 'src/tests/contracts/receipt-safe-dump-fields.ts')
if File.exist?(mirror_path)
  ruby_fields   = File.readlines(File.join(ROOT, 'lib/onetime/models/receipt/features/safe_dump_fields.rb'))
    .reject { |l| l.strip.start_with?('#') }
    .flat_map { |l| l.scan(/safe_dump_field :(\w+)/).flatten }.uniq
  ts_mirror     = File.read(mirror_path).scan(/^\s*'(\w+)',/).flatten.uniq
  missing_in_ts = ruby_fields - ts_mirror
  extra_in_ts   = ts_mirror - ruby_fields
  puts "       Ruby safe_dump fields: #{ruby_fields.size}; TS mirror: #{ts_mirror.size}"
  if missing_in_ts.empty? && extra_in_ts.empty?
    puts '       in sync at this commit'
  else
    puts "       DRIFTED — missing from TS mirror: #{missing_in_ts.inspect}; stale extras: #{extra_in_ts.inspect}"
  end
else
  puts '       mirror deleted (the target architecture retires it) — nothing to compare'
end

puts
if $failures.empty?
  puts "All #{$checks} expectations hold."
else
  puts "FAILED: #{$failures.size} expectation(s):"
  $failures.each { |f| puts "  - #{f}" }
  exit 1
end
