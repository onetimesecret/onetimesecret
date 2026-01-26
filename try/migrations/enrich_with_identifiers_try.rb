# try/migrations/enrich_with_identifiers_try.rb
#
# frozen_string_literal: true

# Tests for the IdentifierEnricher class from the Jan24 migration scripts.
# Validates UUIDv7 generation, extid derivation, and record filtering logic.
#
# Tests cover:
# 1. UUIDv7 generation from timestamp produces valid format
# 2. UUIDv7 timestamp encoding is correct (extractable)
# 3. extid derivation is deterministic
# 4. extid format is correct (prefix + 25 base36 chars)
# 5. Each model gets correct prefix
# 6. Records without :object suffix are skipped
# 7. Records without created field are skipped

require 'json'
require 'securerandom'
require 'digest'

# Load the enricher class directly
load File.expand_path('../../scripts/migrations/jan24/enrich_with_identifiers.rb', __dir__)

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
extid1 = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cu')
extid2 = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cu')
extid1 == extid2
#=> true

## extid format is prefix + 25 base36 characters
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cu')
extid.length == 27 && extid.start_with?('cu')
#=> true

## extid suffix contains only valid base36 characters
uuid = @enricher.send(:generate_uuid_v7_from, @test_timestamp)
extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'sc')
suffix = extid[2..]  # Remove prefix
suffix.match?(/^[0-9a-z]{25}$/)
#=> true

## customer model gets 'cu' prefix
IdentifierEnricher::EXTID_PREFIXES['customer']
#=> 'cu'

## customdomain model gets 'cd' prefix
IdentifierEnricher::EXTID_PREFIXES['customdomain']
#=> 'cd'

## metadata model gets 'rc' prefix (receipt)
IdentifierEnricher::EXTID_PREFIXES['metadata']
#=> 'rc'

## secret model gets 'sc' prefix
IdentifierEnricher::EXTID_PREFIXES['secret']
#=> 'sc'

## organization model gets 'on' prefix
IdentifierEnricher::EXTID_PREFIXES['organization']
#=> 'on'

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
@enricher.send(:enrich_record!, record, 'cu')
record.key?('objid') && record.key?('extid')
#=> true

## enriched record objid is valid UUIDv7 format
record = { 'key' => 'customer:abc123:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'cu')
record['objid'].match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
#=> true

## enriched record extid starts with correct prefix
record = { 'key' => 'secret:xyz789:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'sc')
record['extid'].start_with?('sc')
#=> true

## enriched record extid has correct length
record = { 'key' => 'metadata:def456:object', 'created' => 1705320000 }
@enricher.send(:enrich_record!, record, 'rc')
record['extid'].length == 27
#=> true

## different prefixes produce different extids for same UUID
uuid = '01234567-89ab-7cde-8f01-23456789abcd'
cu_extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cu')
sc_extid = @enricher.send(:derive_extid_from_uuid, uuid, prefix: 'sc')
# Same suffix, different prefix
cu_extid[2..] == sc_extid[2..] && cu_extid[0..1] != sc_extid[0..1]
#=> true

## MODELS_TO_ENRICH includes the expected models
expected = %w[customer customdomain metadata secret]
IdentifierEnricher::MODELS_TO_ENRICH.sort == expected.sort
#=> true

## organization is NOT in MODELS_TO_ENRICH (generated during org creation)
IdentifierEnricher::MODELS_TO_ENRICH.include?('organization')
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
extid = @enricher.send(:derive_extid_from_uuid, min_uuid, prefix: 'cu')
extid.length == 27 && extid.start_with?('cu')
#=> true

## extid derivation handles edge case: maximum UUID
max_uuid = 'ffffffff-ffff-7fff-bfff-ffffffffffff'
extid = @enricher.send(:derive_extid_from_uuid, max_uuid, prefix: 'sc')
extid.length == 27 && extid.start_with?('sc')
#=> true
