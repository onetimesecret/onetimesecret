# try/migrations/enrich_with_identifiers_try.rb
#
# frozen_string_literal: true

# Tests for the IdentifierEnricher class from the 2026-01-26 migration scripts.
# Validates UUIDv7 generation, extid derivation, and record filtering logic.
#
# Tests cover:
# 1. UUIDv7 generation from timestamp produces valid format
# 2. UUIDv7 timestamp encoding is correct (extractable)
# 3. extid derivation is deterministic
# 4. extid format is correct (prefix + 25 base36 chars)
# 5. ObjectIdentifier models get correct prefix (customer=ur, customdomain=cd)
# 6. Records without :object suffix are skipped
# 7. Records without created field are skipped
#
# Note: Only ObjectIdentifier models (customer, customdomain) get objid/extid.
# Receipt and Secret use VerifiableIdentifier (custom generator, no extid).

require 'json'
require 'securerandom'
require 'digest'

# Load the enricher class directly
load File.expand_path('../../scripts/migrations/2026-01-26/enrich_with_identifiers.rb', __dir__)

# Setup
@enricher = IdentifierEnricher.new(input_dir: 'exports', output_dir: 'exports', dry_run: true)

# Known timestamp for reproducible tests (2024-01-15 12:00:00 UTC)
@test_timestamp = 1705320000

# TRYOUTS

## UUIDv7 has valid format (8-4-4-4-12 hex with hyphens)
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
uuid.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
#=> true

## UUIDv7 version nibble is 7
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
uuid.split('-')[2][0]
#=> '7'

## UUIDv7 variant bits are correct (8, 9, a, or b in position 19)
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
variant_char = uuid.split('-')[3][0]
['8', '9', 'a', 'b'].include?(variant_char)
#=> true

## UUIDv7 timestamp is extractable from first 48 bits
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
parts = uuid.split('-')
hex_timestamp = parts[0] + parts[1]  # First 12 hex chars = 48 bits
extracted_ms = hex_timestamp.to_i(16)
expected_ms = (@test_timestamp.to_f * 1000).to_i
extracted_ms == expected_ms
#=> true

## UUIDv7 generates unique random parts for same timestamp
uuid1 = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
uuid2 = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
# Same timestamp in first 13 chars (8 + hyphen + 4), different random parts
uuid1[0..12] == uuid2[0..12] && uuid1 != uuid2
#=> true

## extid derivation is deterministic (same UUID always produces same extid)
uuid = '01234567-89ab-7cde-8f01-23456789abcd'
extid1 = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
extid2 = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
extid1 == extid2
#=> true

## extid format is prefix + 25 base36 characters
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
extid.length == 27 && extid.start_with?('ur')
#=> true

## extid suffix contains only valid base36 characters
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cd')
suffix = extid[2..]  # Remove prefix
suffix.match?(/^[0-9a-z]{25}$/)
#=> true

## customer model gets 'ur' prefix (matches Familia format 'ur%<id>s')
IdentifierEnricher::EXTID_PREFIXES['customer']
#=> 'ur'

## customdomain model gets 'cd' prefix (matches Familia format 'cd%<id>s')
IdentifierEnricher::EXTID_PREFIXES['customdomain']
#=> 'cd'

## organization model gets 'on' prefix (matches Familia format 'on%<id>s')
IdentifierEnricher::EXTID_PREFIXES['organization']
#=> 'on'

## metadata/secret are NOT in EXTID_PREFIXES (use VerifiableIdentifier, not ObjectIdentifier)
IdentifierEnricher::EXTID_PREFIXES.key?('metadata')
#=> false

## secret is NOT in EXTID_PREFIXES (uses VerifiableIdentifier)
IdentifierEnricher::EXTID_PREFIXES.key?('secret')
#=> false

## should_enrich? returns true for :object records with created timestamp
record = { 'key' => 'customer:abc123:object', 'created' => 1705320000 }
@enricher.send(:should_enrich?, record)
#=> true

## should_enrich? returns false for records without :object suffix
record = { 'key' => 'customer:abc123:metadata', 'created' => 1705320000 }
@enricher.send(:should_enrich?, record)
#=> false

## should_enrich? returns falsey for records with nil created
record = { 'key' => 'customer:abc123:object', 'created' => nil }
!@enricher.send(:should_enrich?, record)
#=> true

## should_enrich? returns false for records with zero created
record = { 'key' => 'customer:abc123:object', 'created' => 0 }
@enricher.send(:should_enrich?, record)
#=> false

## should_enrich? returns false for records with negative created
record = { 'key' => 'customer:abc123:object', 'created' => -1 }
@enricher.send(:should_enrich?, record)
#=> false

## should_enrich? returns falsey for records without created field
record = { 'key' => 'customer:abc123:object' }
!@enricher.send(:should_enrich?, record)
#=> true

## should_enrich? returns falsey for records without key field
record = { 'created' => 1705320000 }
!@enricher.send(:should_enrich?, record)
#=> true

## enrich_record! adds objid and extid to record
record = { 'key' => 'customer:abc123:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'ur')
record.key?('objid') && record.key?('extid')
#=> true

## enriched record objid is valid UUIDv7 format
record = { 'key' => 'customer:abc123:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'ur')
record['objid'].match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
#=> true

## enriched record extid starts with correct prefix for customer
record = { 'key' => 'customer:xyz789:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'ur')
record['extid'].start_with?('ur')
#=> true

## enriched record extid starts with correct prefix for customdomain
record = { 'key' => 'customdomain:def456:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'cd')
record['extid'].start_with?('cd')
#=> true

## enriched record extid has correct length
record = { 'key' => 'customdomain:def456:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'cd')
record['extid'].length == 27
#=> true

## different prefixes produce different extids for same UUID
uuid = '01234567-89ab-7cde-8f01-23456789abcd'
ur_extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
cd_extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cd')
# Same suffix, different prefix
ur_extid[2..] == cd_extid[2..] && ur_extid[0..1] != cd_extid[0..1]
#=> true

## MODELS_TO_ENRICH only includes ObjectIdentifier models (not metadata/secret)
expected = %w[customer customdomain]
IdentifierEnricher::MODELS_TO_ENRICH.sort == expected.sort
#=> true

## organization is NOT in MODELS_TO_ENRICH (generated during org creation)
IdentifierEnricher::MODELS_TO_ENRICH.include?('organization')
#=> false

## metadata is NOT in MODELS_TO_ENRICH (uses VerifiableIdentifier)
IdentifierEnricher::MODELS_TO_ENRICH.include?('metadata')
#=> false

## secret is NOT in MODELS_TO_ENRICH (uses VerifiableIdentifier)
IdentifierEnricher::MODELS_TO_ENRICH.include?('secret')
#=> false

## UUIDv7 from different timestamps produces different UUIDs
uuid1 = @enricher.send(:generate_uuid_v7_from, 1705320000)
uuid2 = @enricher.send(:generate_uuid_v7_from, 1705406400)
uuid1[0..12] != uuid2[0..12]  # Different timestamp portion
#=> true

## UUIDv7 preserves chronological ordering in timestamp portion
ts1 = 1705320000  # Earlier
ts2 = 1705406400  # Later
uuid1 = @enricher.send(:generate_uuid_v7_from, ts1)
uuid2 = @enricher.send(:generate_uuid_v7_from, ts2)
# Extract and compare timestamp portions
ts_hex1 = uuid1.split('-')[0] + uuid1.split('-')[1]
ts_hex2 = uuid2.split('-')[0] + uuid2.split('-')[1]
ts_hex1.to_i(16) < ts_hex2.to_i(16)
#=> true

## extid derivation handles edge case: minimum UUID
min_uuid = '00000000-0000-7000-8000-000000000000'
extid = @enricher.send(:derive_extid_from_uuid, min_uuid, prefix: 'ur')
extid.length == 27 && extid.start_with?('ur')
#=> true

## extid derivation handles edge case: maximum UUID
max_uuid = 'ffffffff-ffff-7fff-bfff-ffffffffffff'
extid = @enricher.send(:derive_extid_from_uuid, max_uuid, prefix: 'cd')
extid.length == 27 && extid.start_with?('cd')
#=> true
