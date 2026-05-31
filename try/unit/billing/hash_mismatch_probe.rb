# try/unit/billing/hash_mismatch_probe.rb
#
# frozen_string_literal: true
#
# STANDALONE diagnostic probe for the CI-only hash mismatch in
# org_limit_materialization_try.rb (stored 0b0053014180 != expected 823cf91436e6
# for ["create_secrets","custom_domains"]).
#
# This is NOT a tryouts file. It is a plain Ruby script that boots the same way
# the failing test does, reproduces the materialize sequence, and dumps a battery
# of diagnostics to STDERR. Run directly:
#
#   bundle exec ruby try/unit/billing/hash_mismatch_probe.rb
#
# In CI, prefix with database tracing to capture every Redis command:
#
#   DEBUG_DATABASE=true DEBUG_LOGGERS=Familia:trace \
#     bundle exec ruby try/unit/billing/hash_mismatch_probe.rb
#
# WHY STANDALONE: running outside the tryouts suite isolates the org from
# cross-spec shared-DB ordering. If the mismatch reproduces here, it is intrinsic
# to the materialize path; if it does NOT, the cause is test-ordering pollution.
#
# The centerpiece probe records EVERY call to entitlements_content_hash (input,
# result, caller) across the whole create!→materialize sequence. The record whose
# result == the bad stored hash names the exact writer.

# Unlike a tryouts file (run via `bundle exec try`, whose runner puts lib/ on
# the load path), this is run with `bundle exec ruby`, which does not. Mirror the
# Rakefile and add lib/ before requiring test_helpers (which `require 'onetime'`).
$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__))

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/lib/test_support/billing_helpers'
require_relative '../../../apps/web/billing/operations/apply_subscription_to_org'

PLAN_ID = 'hash_probe_v1'
EXPECTED_ENTS = %w[create_secrets custom_domains].freeze

def warnln(label, value)
  warn "[PROBE] #{label}: #{value}"
end

def banner(text)
  warn "\n[PROBE] ===== #{text} ====="
end

# ---------------------------------------------------------------------------
# Record every entitlements_content_hash call with input, result, and caller.
# Installed BEFORE org creation so it captures create!'s standalone
# materialization, the explicit plan materialize, and any other writer.
# ---------------------------------------------------------------------------
$hash_calls = []
$setter_calls = []

# Instrument the hash function
_original_hash = Onetime::Organization.method(:entitlements_content_hash)
Onetime::Organization.define_singleton_method(:entitlements_content_hash) do |ents|
  result = _original_hash.call(ents)
  $hash_calls << {
    input: (ents.dup rescue ents),
    input_sorted: (ents.sort rescue ents),
    input_classes: (ents.map { |e| e.class.name }.uniq rescue ['?']),
    input_inspect: (ents.map(&:inspect) rescue [ents.inspect]),
    result: result,
    caller: caller(1..6),
  }
  result
end

# Instrument the setter for materialized_entitlements_at
# This catches ANYTHING that writes to this field
Onetime::Organization.class_eval do
  alias_method :_orig_materialized_entitlements_at=, :materialized_entitlements_at=
  define_method(:materialized_entitlements_at=) do |value|
    $setter_calls << {
      value: value,
      caller: caller(1..8),
    }
    send(:_orig_materialized_entitlements_at=, value)
  end
end

banner 'BOOT / CONFIG'
warnln 'DEBUG_DATABASE', ENV['DEBUG_DATABASE'].inspect
warnln 'DEBUG_LOGGERS', ENV['DEBUG_LOGGERS'].inspect
warnln 'Familia.uri', Familia.uri.to_s

# Check source file for line number sanity
mat_ents_file = File.expand_path('../../lib/onetime/models/organization/features/with_materialized_entitlements.rb', __dir__)
if File.exist?(mat_ents_file)
  lines = File.readlines(mat_ents_file)
  warnln 'with_materialized_entitlements.rb total lines', lines.size
  # Find the def lines
  lines.each_with_index do |line, idx|
    if line =~ /def materialize_entitlements_from_plan/
      warnln 'materialize_from_plan def line', (idx + 1)
    elsif line =~ /def materialize_entitlements_from_config/
      warnln 'materialize_from_config def line', (idx + 1)
    end
  end
else
  warnln 'mat_ents_file', "NOT FOUND: #{mat_ents_file}"
end

# Enable Familia database logging to see raw Redis commands
# This must be done before any Redis operations
if ENV['DEBUG_DATABASE']
  Familia.enable_database_logging = true
  warnln 'Familia.enable_database_logging', Familia.enable_database_logging.inspect
end

# ---------------------------------------------------------------------------
# Reproduce the failing test's setup
# ---------------------------------------------------------------------------
BillingTestHelpers.restore_billing!(enabled: true)
warnln 'billing_enabled? (BillingConfig)', Onetime::BillingConfig.instance.enabled?

BillingTestHelpers.populate_test_plans([
  {
    plan_id: PLAN_ID,
    name: 'Hash Probe Plan',
    tier: 'multi_team',
    entitlements: EXPECTED_ENTS,
    limits: { 'teams.max' => 5 },
  },
])

@plan = ::Billing::Plan.load(PLAN_ID)
banner 'PLAN STATE (pre-create)'
warnln 'plan.entitlements.to_a.sort', @plan.entitlements.to_a.sort.inspect
warnln 'plan.entitlements.dbkey', @plan.entitlements.dbkey
warnln 'raw smembers(plan ent dbkey)', Familia.dbclient.smembers(@plan.entitlements.dbkey).sort.inspect

# Create org + owner exactly like make_org in the failing test.
owner = Onetime::Customer.create!("hash-probe-#{Familia.now.to_i}@example.com")
banner 'ORG CREATION'
warnln 'hash_calls BEFORE create!', $hash_calls.size
org = Onetime::Organization.create!('Hash Probe Org', owner)
warnln 'hash_calls AFTER create!', $hash_calls.size
warnln 'org.billing_enabled? at create time', org.billing_enabled?
warnln 'materialized_entitlements_at after create!', org.materialized_entitlements_at.inspect

org.planid = PLAN_ID
org.save

# Reload the plan the same way the test does, then materialize.
@plan_at_materialize = ::Billing::Plan.load(PLAN_ID)
banner 'EXPLICIT MATERIALIZE'
warnln 'plan_at_materialize.entitlements.to_a.sort', @plan_at_materialize.entitlements.to_a.sort.inspect
warnln 'hash_calls BEFORE materialize', $hash_calls.size
warnln 'setter_calls BEFORE materialize', $setter_calls.size

# Log method resolution
mat_method = org.method(:materialize_entitlements_from_plan)
warnln 'materialize_from_plan method owner', mat_method.owner.to_s
warnln 'materialize_from_plan method source', mat_method.source_location.inspect

mat_config_method = org.method(:materialize_entitlements_from_config)
warnln 'materialize_from_config method owner', mat_config_method.owner.to_s
warnln 'materialize_from_config method source', mat_config_method.source_location.inspect

standalone_method = org.method(:materialize_standalone_entitlements!)
warnln 'standalone method owner', standalone_method.owner.to_s
warnln 'standalone method source', standalone_method.source_location.inspect

hash_method = org.class.method(:entitlements_content_hash)
warnln 'hash method owner', hash_method.owner.to_s
warnln 'hash method source', hash_method.source_location.inspect

# Also log org's billing state
warnln 'org.billing_enabled?', org.billing_enabled?.inspect
warnln 'org.planid', org.planid.inspect

org.materialize_entitlements_from_plan(@plan_at_materialize)
warnln 'hash_calls AFTER materialize', $hash_calls.size
warnln 'setter_calls AFTER materialize', $setter_calls.size

# Raw Redis read immediately after materialize
raw_mat_at = Familia.dbclient.hget(org.dbkey, 'materialized_entitlements_at')
warnln 'raw HGET materialized_entitlements_at (immediate)', raw_mat_at.inspect
warnln 'org.dbkey', org.dbkey.inspect

# ---------------------------------------------------------------------------
# PROBE 0 — ALL setter calls (catches any write to the field)
# ---------------------------------------------------------------------------
banner 'PROBE 0 — ALL materialized_entitlements_at= SETTER CALLS'
$setter_calls.each_with_index do |c, i|
  warn "[PROBE] setter call ##{i} value=#{c[:value].inspect}"
  warn "[PROBE]   caller=#{c[:caller].inspect}"
end

# ---------------------------------------------------------------------------
# PROBE 1: every hash computation, in order, with caller. The record whose
# result matches the stored hash is the writer that wins.
# ---------------------------------------------------------------------------
banner 'PROBE 1 — ALL entitlements_content_hash CALLS'
$hash_calls.each_with_index do |c, i|
  warn "[PROBE] call ##{i} result=#{c[:result]}"
  warn "[PROBE]   input_sorted=#{c[:input_sorted].inspect}"
  warn "[PROBE]   input_classes=#{c[:input_classes].inspect}"
  warn "[PROBE]   input_inspect=#{c[:input_inspect].inspect}"
  warn "[PROBE]   caller=#{c[:caller].inspect}"
end

# ---------------------------------------------------------------------------
# PROBE 2 (KEYSTONE): stored hash vs the result the hash fn actually returned
# during the explicit materialize. If equal but wrong, the input was wrong.
# If stored != last result, a DIFFERENT writer clobbered the field afterward.
# ---------------------------------------------------------------------------
banner 'PROBE 2 — KEYSTONE stored vs computed'
parsed = org.send(:materialized_entitlements_at_parsed)
stored_hash = parsed && parsed[:content_hash]
last_result = $hash_calls.last && $hash_calls.last[:result]
expected_hash = Onetime::Organization.entitlements_content_hash(EXPECTED_ENTS)
warnln 'stored_hash', stored_hash.inspect
warnln 'last_computed_hash', last_result.inspect
warnln 'expected_hash', expected_hash.inspect
warnln 'stored == last_computed?', (stored_hash == last_result)
warnln 'stored == expected?', (stored_hash == expected_hash)
warnln 'raw materialized_entitlements_at', org.materialized_entitlements_at.inspect

# ---------------------------------------------------------------------------
# PROBE 3: Familia .to_a vs raw Redis smembers for the plan's entitlements.
# Catches a Familia read returning different data than what is persisted.
# ---------------------------------------------------------------------------
banner 'PROBE 3 — Familia .to_a vs raw Redis (plan)'
warnln 'plan.entitlements.to_a.sort', @plan_at_materialize.entitlements.to_a.sort.inspect
warnln 'raw smembers(plan ent dbkey)', Familia.dbclient.smembers(@plan_at_materialize.entitlements.dbkey).sort.inspect

# ---------------------------------------------------------------------------
# PROBE 4: what was persisted into the org's own entitlements_plan set.
# ---------------------------------------------------------------------------
banner 'PROBE 4 — org persisted sets'
warnln 'org.entitlements_plan.to_a.sort', org.entitlements_plan.to_a.sort.inspect
warnln 'raw smembers(org entitlements_plan dbkey)', Familia.dbclient.smembers(org.entitlements_plan.dbkey).sort.inspect
warnln 'org.materialized_entitlements.to_a.sort', org.materialized_entitlements.to_a.sort.inspect
warnln 'raw smembers(org materialized_entitlements dbkey)', Familia.dbclient.smembers(org.materialized_entitlements.dbkey).sort.inspect

# ---------------------------------------------------------------------------
# PROBE 5: key-space enumeration. Catches leftover/duplicate keys from prior
# runs (shared-DB pollution) or a family-identity collision on the set key.
# ---------------------------------------------------------------------------
banner 'PROBE 5 — key-space enumeration'
plan_keys = Familia.dbclient.keys("*#{PLAN_ID}*")
warnln "keys('*#{PLAN_ID}*') count", plan_keys.size
plan_keys.sort.each { |k| warn "[PROBE]   #{k}" }

# ---------------------------------------------------------------------------
# PROBE 6: reload org from Redis — in-memory vs persisted.
# ---------------------------------------------------------------------------
banner 'PROBE 6 — reload from Redis'
reloaded = Onetime::Organization.load(org.objid)
warnln 'reloaded.materialized_entitlements_at', reloaded.materialized_entitlements_at.inspect
warnln 'in-memory == reloaded?', (org.materialized_entitlements_at == reloaded.materialized_entitlements_at)

# ---------------------------------------------------------------------------
# PROBE 7: double-read timing. A late/async write would change the value
# between two reads taken back-to-back.
# ---------------------------------------------------------------------------
banner 'PROBE 7 — double read (late-write detection)'
read_a = Onetime::Organization.load(org.objid).materialized_entitlements_at
read_b = Onetime::Organization.load(org.objid).materialized_entitlements_at
warnln 'read_a', read_a.inspect
warnln 'read_b', read_b.inspect
warnln 'read_a == read_b?', (read_a == read_b)

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
banner 'TEARDOWN'
begin
  org.destroy!
  owner.destroy!
  BillingTestHelpers.cleanup_billing_state!
  warnln 'teardown', 'ok'
rescue StandardError => ex
  warnln 'teardown error', "#{ex.class}: #{ex.message}"
end

# Final verdict line for quick grep in CI logs.
verdict =
  if stored_hash == expected_hash
    'PASS (no mismatch reproduced here)'
  elsif stored_hash == last_result
    "MISMATCH from WRONG INPUT (input=#{$hash_calls.last && $hash_calls.last[:input_sorted].inspect})"
  else
    "MISMATCH from CLOBBERING WRITER (stored=#{stored_hash} != last_computed=#{last_result})"
  end
banner "VERDICT: #{verdict}"
