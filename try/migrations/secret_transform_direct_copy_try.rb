# try/migrations/secret_transform_direct_copy_try.rb
#
# frozen_string_literal: true

# Verifies SecretTransformer::DIRECT_COPY_FIELDS preserve raw bytes verbatim
# end-to-end through the v0.24.5 typed-payload (fields_b64) round-trip.
#
# Pre-cleanup the encrypted fields flowed through Redis HMSET -> DUMP, which
# kept bytes opaque. Post-cleanup the path is:
#
#   v1 fields_b64[f]
#     -> Base64.strict_decode64    (in read_v1_hash)
#     -> v1_fields[f] (raw bytes)
#     -> v2_fields[f] = v1_fields[f]            (direct copy, same string)
#     -> serialize_for_v2 -> Familia::JsonSerializer.dump (JSON-encodes the
#        binary string: wraps in quotes and escapes non-printable bytes as
#        \u00xx — output is UTF-8, ~400 bytes for full 0x00..0xff input)
#     -> Base64.strict_encode64    (in transform_secret_object)
#     -> output fields_b64[f]
#
# To recover the original bytes downstream:
#   JSON.parse(Base64.strict_decode64(output_b64))
#
# Failure modes that would silently corrupt every secret in production:
#   - Encoding coercion (force_encoding) BEFORE JSON dump corrupts bytes
#   - JSON.parse of the b64-decoded string returning a different byte sequence
#   - serialize_for_v2 dropping DIRECT_COPY_FIELDS (would lose them entirely)
#
# This test does NOT need Redis. The transformer is instantiated directly and
# transform_secret_object is called via .send (private method).

require 'base64'
require 'json'
require 'securerandom'
require 'tmpdir'

PROJECT_ROOT_SECRET_TRY = File.expand_path('../..', __dir__).freeze

# Load the transformer class without triggering the script's main block
load File.join(PROJECT_ROOT_SECRET_TRY, 'scripts/upgrades/v0.24.5/05-secret/transform.rb')

# --- Fixture builders ---------------------------------------------------------

# Build a 256-byte string covering the full 0x00..0xff range.
def full_byte_range_blob
  (0..255).map(&:chr).join.b
end

# Build a record matching what dump_keys.rb emits: fields_b64 keyed by string,
# raw v1 bytes Base64-encoded.
def v1_secret_record(objid:, fields:)
  fields_b64 = fields.each_with_object({}) do |(k, v), acc|
    acc[k.to_s] = Base64.strict_encode64(v.to_s)
  end
  {
    key: "secret:#{objid}:object",
    type: 'hash',
    ttl_ms: -1,
    db: 0,
    fields_b64: fields_b64,
    objid: objid,
    created: Time.now.to_i,
  }
end

# --- Test setup ---------------------------------------------------------------

# Fixed binary blobs so assertions can compare exactly.
@blob_full_range = full_byte_range_blob
@blob_random_a   = SecureRandom.bytes(256)
@blob_random_b   = SecureRandom.bytes(256)
@blob_random_c   = SecureRandom.bytes(256)
@blob_random_d   = SecureRandom.bytes(256)

@v1_fields = {
  'ciphertext'             => @blob_full_range,
  'value'                  => @blob_random_a,
  'value_encryption'       => @blob_random_b,
  'passphrase'             => @blob_random_c,
  'passphrase_encryption'  => @blob_random_d,
  # Control: a non-DIRECT_COPY field so we exercise serialize_for_v2 alongside.
  'state' => 'previewed',
  # custid='anon' so transform_ownership short-circuits (no load_mappings needed)
  'custid' => 'anon',
}

@objid     = 'secret-objid-test-001'
@v1_record = v1_secret_record(objid: @objid, fields: @v1_fields)

# Instantiate transformer with dummy paths (validate_input_file is only called
# inside run; we bypass that by calling transform_secret_object directly).
@workdir = Dir.mktmpdir('secret_direct_copy_try_')
@xformer = SecretTransformer.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
  exports_dir: @workdir,
)

# Decode the fixture as the transformer's read_v1_hash would.
@v1_decoded = @v1_record[:fields_b64].each_with_object({}) do |(k, b64), acc|
  acc[k.to_s] = Base64.strict_decode64(b64)
end

# Run the actual transform (private method).
@v2_record = @xformer.send(:transform_secret_object, @v1_record, @v1_decoded, @objid)
@out_b64   = @v2_record[:fields_b64]

# Decode each output field for byte-level comparison. After Base64 decoding,
# the value is the JSON-encoded form (quoted, with \u escapes). Apply JSON.parse
# to recover the original raw bytes that downstream consumers see.
@out_b64_decoded = @out_b64.each_with_object({}) do |(k, b64), acc|
  acc[k.to_s] = Base64.strict_decode64(b64)
end

@out_recovered = @out_b64_decoded.each_with_object({}) do |(k, json_str), acc|
  acc[k.to_s] = JSON.parse(json_str)
end

# --- Tests --------------------------------------------------------------------

## Output is a Hash with fields_b64 payload
@v2_record.is_a?(Hash) && @v2_record[:fields_b64].is_a?(Hash)
#=> true

## DIRECT_COPY_FIELDS subset under test all present in output
%w[ciphertext value value_encryption passphrase passphrase_encryption].all? { |f| @out_b64.key?(f) }
#=> true

## ciphertext: full 0x00..0xff byte range recovered byte-exactly via JSON.parse
@out_recovered['ciphertext'].bytes == @blob_full_range.bytes
#=> true

## ciphertext: recovered byte length matches input (256)
@out_recovered['ciphertext'].bytesize
#=> 256

## ciphertext: b64-decoded form IS JSON-wrapped (quote-prefixed)
@out_b64_decoded['ciphertext'].start_with?('"')
#=> true

## value: random 256-byte blob recovered byte-exactly
@out_recovered['value'].bytes == @blob_random_a.bytes
#=> true

## value: bytesize preserved
@out_recovered['value'].bytesize
#=> 256

## value_encryption: random 256-byte blob recovered byte-exactly
@out_recovered['value_encryption'].bytes == @blob_random_b.bytes
#=> true

## passphrase: random 256-byte blob recovered byte-exactly
@out_recovered['passphrase'].bytes == @blob_random_c.bytes
#=> true

## passphrase_encryption: random 256-byte blob recovered byte-exactly
@out_recovered['passphrase_encryption'].bytes == @blob_random_d.bytes
#=> true

## Control field 'state' decoded form IS JSON-encoded
@out_b64_decoded['state']
#=> '"previewed"'

## Control field 'state' recovered value parses to plain string
@out_recovered['state']
#=> 'previewed'

## All five direct-copy blobs preserve their bytes (defensive composite check)
@all_match = %w[ciphertext value value_encryption passphrase passphrase_encryption].all? do |f|
  expected = @v1_fields[f]
  @out_recovered[f].bytes == expected.bytes && @out_recovered[f].bytesize == expected.bytesize
end
@all_match
#=> true
