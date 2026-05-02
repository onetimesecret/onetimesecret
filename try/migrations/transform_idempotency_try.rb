# try/migrations/transform_idempotency_try.rb
#
# frozen_string_literal: true

# Verifies that running each v0.24.5 transform twice on the same input record
# produces a byte-identical fields_b64 payload (after stripping wall-clock and
# truly-random fields).
#
# Idempotency is a contract of the post-cleanup pipeline. Pre-cleanup, the
# transforms touched a temp Redis DB, leaking state across runs. Post-cleanup
# the transforms are pure functions over their input record, modulo two
# documented sources of variation:
#
#   - migrated_at = Time.now.to_f.to_s   (stamped per call by every transformer)
#   - updated, email_hash_synced_at      (organization only, also wall-clock)
#
# Notably, organization extid is DETERMINISTIC: derive_extid_from_uuid is
# SHA256-seeded from the org_objid, which itself is SHA256-seeded from the
# customer_objid + created timestamp. So extid is NOT excluded from the
# comparison — that was a misconception in the original spec.
#
# This test exercises the in-process transform classes directly and avoids the
# shellout path entirely (the shell pipeline is covered separately by
# organization_generation_try.rb).

require 'base64'
require 'json'
require 'tmpdir'

PROJECT_ROOT_IDEMPO_TRY = File.expand_path('../..', __dir__).freeze

load File.join(PROJECT_ROOT_IDEMPO_TRY, 'scripts/upgrades/v0.24.5/01-customer/transform.rb')
load File.join(PROJECT_ROOT_IDEMPO_TRY, 'scripts/upgrades/v0.24.5/02-organization/generate.rb')
load File.join(PROJECT_ROOT_IDEMPO_TRY, 'scripts/upgrades/v0.24.5/03-customdomain/transform.rb')
load File.join(PROJECT_ROOT_IDEMPO_TRY, 'scripts/upgrades/v0.24.5/04-receipt/transform.rb')
load File.join(PROJECT_ROOT_IDEMPO_TRY, 'scripts/upgrades/v0.24.5/05-secret/transform.rb')

# --- Helpers ------------------------------------------------------------------

def make_record(key:, fields:, extras: {})
  fields_b64 = fields.each_with_object({}) do |(k, v), acc|
    acc[k.to_s] = Base64.strict_encode64(v.to_s)
  end
  { key: key, type: 'hash', ttl_ms: -1, db: 0, fields_b64: fields_b64 }.merge(extras)
end

# Drop wall-clock fields (per-transformer list) before comparing. Returns the
# canonical hash of fields_b64 entries that *should* be byte-identical between
# runs.
def stable_b64(fields_b64, drop:)
  fields_b64.reject { |k, _| drop.include?(k.to_s) }
end

# --- Setup --------------------------------------------------------------------

@workdir = Dir.mktmpdir('xform_idempo_try_')

# Customer transformer ---------------------------------------------------------
@customer_v1 = {
  'custid' => 'alice@example.com',
  'email' => 'alice@example.com',
  'planid' => 'free',
  'verified' => 'true',
  'created' => '1700000000.0',
}
@customer_record = make_record(
  key: 'customer:alice@example.com:object',
  fields: @customer_v1,
  extras: { objid: 'cust-objid-001', extid: 'cu-ext-001', created: 1_700_000_000 },
)
@customer_xformer = CustomerTransformer.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
)
@customer_v1_decoded = Upgrade::V1Hash.read(@customer_record, @customer_xformer.instance_variable_get(:@stats)[:errors])
@customer_a = @customer_xformer.send(:transform_customer_object, @customer_record, @customer_v1_decoded.dup, 'cust-objid-001', 'cu-ext-001')
sleep 0.001 # ensure migrated_at could differ; stripped from comparison
@customer_b = @customer_xformer.send(:transform_customer_object, @customer_record, @customer_v1_decoded.dup, 'cust-objid-001', 'cu-ext-001')

# Organization generator -------------------------------------------------------
# NOTE: org generator computes objid + extid deterministically from the
# customer_objid + created timestamp (SHA256 seed). Wall-clock fields stripped:
# migrated_at, updated, email_hash_synced_at.
@org_customer_record = {
  key: 'customer:cust-objid-001:object', objid: 'cust-objid-001', db: 0,
  created: 1_700_000_000,
}
@org_customer_fields = {
  'email' => 'alice@example.com', 'v1_custid' => 'alice@example.com',
  'planid' => 'free', 'created' => '1700000000.0',
}
@org_gen = OrganizationGenerator.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
)
@org_a = @org_gen.send(:generate_organization, 'cust-objid-001', @org_customer_fields, @org_customer_record)
sleep 0.001
@org_b = @org_gen.send(:generate_organization, 'cust-objid-001', @org_customer_fields, @org_customer_record)

# CustomDomain transformer -----------------------------------------------------
# Inject empty mappings to bypass load_mappings.
@cd_xformer = CustomDomainTransformer.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
  email_to_org_file: File.join(@workdir, 'noop.json'),
  email_to_customer_file: nil,
)
@cd_xformer.instance_variable_set(:@email_to_org, { 'alice@example.com' => 'org-objid-001' })
@cd_xformer.instance_variable_set(:@email_to_customer, {})
@cd_v1 = {
  'domainid' => 'dom-001',
  'display_domain' => 'example.com',
  'custid' => 'alice@example.com',
  'created' => '1700000000.0',
}
@cd_record = make_record(
  key: 'customdomain:dom-001:object',
  fields: @cd_v1,
  extras: { objid: 'dom-objid-001', extid: 'cd-ext-001', created: 1_700_000_000 },
)
@cd_decoded = Upgrade::V1Hash.read(@cd_record, @cd_xformer.instance_variable_get(:@stats)[:errors])
@cd_a = @cd_xformer.send(:transform_domain_object, @cd_record, @cd_decoded.dup, 'dom-objid-001', 'cd-ext-001')
sleep 0.001
@cd_b = @cd_xformer.send(:transform_domain_object, @cd_record, @cd_decoded.dup, 'dom-objid-001', 'cd-ext-001')

# Receipt transformer ----------------------------------------------------------
@receipt_xformer = ReceiptTransformer.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
  exports_dir: @workdir,
)
@receipt_xformer.instance_variable_set(:@email_to_customer, {})
@receipt_xformer.instance_variable_set(:@email_to_org, {})
@receipt_xformer.instance_variable_set(:@fqdn_to_domain, {})
@receipt_v1 = {
  'custid' => 'anon',
  'state' => 'viewed',
  'lifespan' => '3600',
  'secret_ttl' => '3600',
  'created' => '1700000000.0',
}
@receipt_record = make_record(
  key: 'metadata:rcpt-001:object',
  fields: @receipt_v1,
  extras: { created: 1_700_000_000 },
)
@receipt_decoded = Upgrade::V1Hash.read(@receipt_record, @receipt_xformer.instance_variable_get(:@stats)[:errors])
@receipt_a = @receipt_xformer.send(:transform_receipt_object, @receipt_record, @receipt_decoded.dup, 'rcpt-001')
sleep 0.001
@receipt_b = @receipt_xformer.send(:transform_receipt_object, @receipt_record, @receipt_decoded.dup, 'rcpt-001')

# Secret transformer -----------------------------------------------------------
@secret_xformer = SecretTransformer.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
  exports_dir: @workdir,
)
@secret_xformer.instance_variable_set(:@email_to_customer, {})
@secret_xformer.instance_variable_set(:@email_to_org, {})
@secret_xformer.instance_variable_set(:@fqdn_to_domain, {})
@secret_v1 = {
  'custid' => 'anon',
  'state' => 'viewed',
  'ciphertext' => 'YWJjZGVm', # ASCII-safe sample
  'lifespan' => '3600',
  'created' => '1700000000.0',
}
@secret_record = make_record(
  key: 'secret:sec-001:object',
  fields: @secret_v1,
  extras: { created: 1_700_000_000 },
)
@secret_decoded = Upgrade::V1Hash.read(@secret_record, @secret_xformer.instance_variable_get(:@stats)[:errors])
@secret_a = @secret_xformer.send(:transform_secret_object, @secret_record, @secret_decoded.dup, 'sec-001')
sleep 0.001
@secret_b = @secret_xformer.send(:transform_secret_object, @secret_record, @secret_decoded.dup, 'sec-001')

# Wall-clock fields stripped for the comparison. All transforms write
# migrated_at; OrganizationGenerator additionally writes updated +
# email_hash_synced_at.
DROP_COMMON = %w[migrated_at].freeze
DROP_ORG    = %w[migrated_at updated email_hash_synced_at].freeze

# --- Tests --------------------------------------------------------------------

## Customer: stable fields_b64 byte-identical between two runs
stable_b64(@customer_a[:fields_b64], drop: DROP_COMMON) == stable_b64(@customer_b[:fields_b64], drop: DROP_COMMON)
#=> true

## Customer: top-level :objid stable
@customer_a[:objid] == @customer_b[:objid]
#=> true

## Organization: stable fields_b64 byte-identical (extid IS deterministic)
stable_b64(@org_a[:fields_b64], drop: DROP_ORG) == stable_b64(@org_b[:fields_b64], drop: DROP_ORG)
#=> true

## Organization: extid deterministic across runs
@org_a[:extid] == @org_b[:extid]
#=> true

## Organization: objid deterministic across runs
@org_a[:objid] == @org_b[:objid]
#=> true

## CustomDomain: stable fields_b64 byte-identical between runs
stable_b64(@cd_a[:fields_b64], drop: DROP_COMMON) == stable_b64(@cd_b[:fields_b64], drop: DROP_COMMON)
#=> true

## Receipt: stable fields_b64 byte-identical between runs
stable_b64(@receipt_a[:fields_b64], drop: DROP_COMMON) == stable_b64(@receipt_b[:fields_b64], drop: DROP_COMMON)
#=> true

## Receipt: state transformation is deterministic (viewed -> previewed)
state_a = JSON.parse(Base64.strict_decode64(@receipt_a[:fields_b64]['state']))
state_b = JSON.parse(Base64.strict_decode64(@receipt_b[:fields_b64]['state']))
[state_a, state_b]
#=> ['previewed', 'previewed']

## Secret: stable fields_b64 byte-identical between runs
stable_b64(@secret_a[:fields_b64], drop: DROP_COMMON) == stable_b64(@secret_b[:fields_b64], drop: DROP_COMMON)
#=> true

## Secret: ciphertext byte-identical between runs (defensive R1 cross-check)
@secret_a[:fields_b64]['ciphertext'] == @secret_b[:fields_b64]['ciphertext']
#=> true
