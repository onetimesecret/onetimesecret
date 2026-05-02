# try/migrations/customdomain_related_hash_types_try.rb
#
# frozen_string_literal: true

# Verifies CustomDomainTransformer's two type-conversion contracts:
#
#   1. transform_related_hash (brand/logo/icon) uses parse_related_field, which
#      is LENIENT — unknown keys passthrough as JSON-encoded string. This is
#      defended at lines 499-503 of 03-customdomain/transform.rb. The brand and
#      image hash schemas are extensible at the model layer, so unknown keys
#      should not blow up the whole record.
#
#   2. serialize_for_v2 (top-level domain object) uses parse_to_ruby_type, which
#      is FAIL-FAST — any field name not in FIELD_TYPES raises ArgumentError
#      (lines 484-487). This catches schema drift at the migration boundary.
#
# Also locks in the empty-string -> 'null' convention shared by both paths
# (lines 414-415 for related, 458-459 for top-level).
#
# Output values are inspected as JSON-decoded strings (after Base64 decode) so
# the assertions read naturally; the production wire format is base64(JSON(value)).

require 'base64'
require 'json'
require 'tmpdir'

PROJECT_ROOT_CD_TRY = File.expand_path('../..', __dir__).freeze

# Load the transformer class without triggering the script's main block
load File.join(PROJECT_ROOT_CD_TRY, 'scripts/upgrades/v0.24.5/03-customdomain/transform.rb')

# --- Fixture builders ---------------------------------------------------------

def cd_record(key:, fields:)
  fields_b64 = fields.each_with_object({}) do |(k, v), acc|
    acc[k.to_s] = Base64.strict_encode64(v.to_s)
  end
  { key: key, type: 'hash', ttl_ms: -1, db: 0, fields_b64: fields_b64 }
end

def decode_b64_map(map)
  map.each_with_object({}) { |(k, b64), acc| acc[k.to_s] = Base64.strict_decode64(b64) }
end

# --- Test setup ---------------------------------------------------------------

@workdir = Dir.mktmpdir('cd_related_hash_try_')

# Instantiate transformer with dummy paths; load_mappings is only called from
# .run, which we never invoke. Methods under test (transform_related_hash and
# serialize_for_v2) are private — call via .send.
@xformer = CustomDomainTransformer.new(
  input_file: File.join(@workdir, 'noop.jsonl'),
  output_dir: @workdir,
  email_to_org_file: File.join(@workdir, 'noop.json'),
  email_to_customer_file: nil,
)

# Brand record: 4 known typed fields covering string/boolean/integer + empty
# string + an unknown key that should survive the lenient passthrough.
@brand_v1 = {
  'primary_color'       => 'red',
  'passphrase_required' => 'true',
  'default_ttl'         => '3600',
  'description'         => '',
  'unknown_extra'       => 'whatever',
}
@brand_record = cd_record(key: 'customdomain:dom123:brand', fields: @brand_v1)
@brand_v2     = @xformer.send(:transform_related_hash, @brand_record, 'objid-cd-001', 'brand')
@brand_out    = decode_b64_map(@brand_v2[:fields_b64])

# Logo record: integer/float/string fields under IMAGE_FIELD_TYPES.
@logo_v1 = {
  'bytes'    => '12345',
  'ratio'    => '1.5',
  'filename' => 'logo.png',
}
@logo_record = cd_record(key: 'customdomain:dom123:logo', fields: @logo_v1)
@logo_v2     = @xformer.send(:transform_related_hash, @logo_record, 'objid-cd-001', 'logo')
@logo_out    = decode_b64_map(@logo_v2[:fields_b64])

# --- Tests: brand related hash (lenient parse_related_field) ------------------

## brand: primary_color (string) JSON-encoded as quoted string
@brand_out['primary_color']
#=> '"red"'

## brand: passphrase_required (boolean) decoded as JSON true literal
@brand_out['passphrase_required']
#=> 'true'

## brand: default_ttl (integer) decoded as JSON integer literal
@brand_out['default_ttl']
#=> '3600'

## brand: description (empty string) collapses to JSON null
@brand_out['description']
#=> 'null'

## brand: unknown_extra is LENIENT passthrough — encoded as quoted string
@brand_out['unknown_extra']
#=> '"whatever"'

## brand: output key is renamed to custom_domain:{objid}:brand (underscore added)
@brand_v2[:key]
#=> 'custom_domain:objid-cd-001:brand'

# --- Tests: logo related hash -------------------------------------------------

## logo: bytes (integer) decoded as JSON integer literal
@logo_out['bytes']
#=> '12345'

## logo: ratio (float) decoded as JSON float literal
@logo_out['ratio']
#=> '1.5'

## logo: filename (string) JSON-encoded as quoted string
@logo_out['filename']
#=> '"logo.png"'

## logo: output key is renamed with underscore
@logo_v2[:key]
#=> 'custom_domain:objid-cd-001:logo'

# --- Tests: top-level serialize_for_v2 is FAIL-FAST ---------------------------

## Unknown top-level field raises ArgumentError
@xformer.send(:serialize_for_v2, { 'totally_unknown' => 'x' })
#=!> ArgumentError

## Unknown top-level field error message names the field
begin
  @xformer.send(:serialize_for_v2, { 'totally_unknown' => 'x' })
  :no_raise
rescue ArgumentError => ex
  ex.message.include?('Unknown field') && ex.message.include?('totally_unknown')
end
#=> true

## Top-level known field still works (objid is :string)
@xformer.send(:serialize_for_v2, { 'objid' => 'abc' })
#=> { 'objid' => '"abc"' }

## Top-level empty-string convention also collapses to null
@xformer.send(:serialize_for_v2, { 'display_domain' => '' })
#=> { 'display_domain' => 'null' }
