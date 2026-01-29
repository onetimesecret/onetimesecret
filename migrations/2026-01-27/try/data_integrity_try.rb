# try/migrations/data_integrity_try.rb
#
# Integration tests for data integrity through the migration pipeline.
# Tests binary preservation, DUMP/RESTORE round-trips, and field consistency.
#
# Requires running Redis for restore/dump operations.
#
# frozen_string_literal: true

require_relative '../../../try/support/test_helpers'
require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'tmpdir'

OT.boot! :test, true

# Get Redis config from OT.conf
redis_uri = URI.parse(OT.conf['redis']['uri'])
@redis_host = redis_uri.host
@redis_port = redis_uri.port
@test_db = 14
@scratch_db = 15

MIGRATION_DIR = File.expand_path('..', __dir__)

## Base64 encoding/decoding round-trip preserves data
original_data = "test data with special chars: \x00\xFF\xFE".force_encoding('ASCII-8BIT')
encoded = Base64.strict_encode64(original_data)
decoded = Base64.strict_decode64(encoded)

# Force same encoding for comparison
original_data.bytes == decoded.bytes
#=> true

## Redis DUMP/RESTORE preserves hash field values
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

# Create a hash with various field types
@redis.hset('test:hash', 'string_field', 'hello world')
@redis.hset('test:hash', 'numeric_field', '12345')
@redis.hset('test:hash', 'email_field', 'user@example.com')

# Dump and restore to different key
dump_data = @redis.dump('test:hash')
@redis.restore('test:hash:restored', 0, dump_data)

# Compare fields
original_fields = @redis.hgetall('test:hash')
restored_fields = @redis.hgetall('test:hash:restored')

original_fields == restored_fields
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Base64 DUMP round-trip preserves data through JSONL
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.hset('test:hash', 'field1', 'value1')
@redis.hset('test:hash', 'field2', 'value2')

# Simulate JSONL export/import
dump_data = @redis.dump('test:hash')
dump_b64 = Base64.strict_encode64(dump_data)

# This is what gets written to JSONL
jsonl_record = JSON.generate({
  key: 'test:hash',
  type: 'hash',
  dump: dump_b64
})

# Parse back (simulating load)
parsed = JSON.parse(jsonl_record)
restored_dump = Base64.strict_decode64(parsed['dump'])

# Restore and verify
@redis.restore('test:hash:from_jsonl', 0, restored_dump)
fields = @redis.hgetall('test:hash:from_jsonl')

[fields['field1'], fields['field2']]
#=> ["value1", "value2"]

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## TTL preservation: -1 means no expiry
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.set('test:key', 'value')

# No TTL set, should be -1
ttl = @redis.pttl('test:key')
ttl
#=> -1

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## TTL preservation: positive value for expiring keys
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.set('test:key', 'value', ex: 3600)  # 1 hour

# Should have positive TTL (in ms)
ttl = @redis.pttl('test:key')
ttl > 0 && ttl <= 3600000
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Binary data in hash fields preserved through DUMP/RESTORE
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

# Create binary data that might be ciphertext
binary_data = "\x00\x01\x02\xFE\xFF".force_encoding('ASCII-8BIT') + SecureRandom.random_bytes(32)

@redis.hset('test:binary', 'ciphertext', binary_data)
@redis.hset('test:binary', 'text_field', 'normal text')

# Dump and restore
dump_data = @redis.dump('test:binary')
@redis.restore('test:binary:restored', 0, dump_data)

# Verify binary field preserved exactly (compare bytes to avoid encoding issues)
restored_binary = @redis.hget('test:binary:restored', 'ciphertext')

binary_data.bytes == restored_binary.bytes
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Hash field order does not affect DUMP content comparison
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

# Redis hashes don't guarantee field order, so we verify values not dump equality
@redis.hmset('test:hash1', 'a', '1', 'b', '2', 'c', '3')
@redis.hmset('test:hash2', 'c', '3', 'a', '1', 'b', '2')  # Different order

fields1 = @redis.hgetall('test:hash1')
fields2 = @redis.hgetall('test:hash2')

fields1 == fields2
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## RESTORE with REPLACE overwrites existing key
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

# Create original
@redis.hset('test:key', 'field', 'original_value')

# Create new data and dump it
@redis.hset('test:source', 'field', 'new_value')
dump_data = @redis.dump('test:source')

# Restore over existing key with REPLACE
@redis.restore('test:key', 0, dump_data, replace: true)

# Should have new value
@redis.hget('test:key', 'field')
#=> "new_value"

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## RESTORE without REPLACE fails on existing key
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.set('test:key', 'existing')
@redis.set('test:source', 'new')
dump_data = @redis.dump('test:source')

begin
  @redis.restore('test:key', 0, dump_data)  # No replace flag
  false
rescue Redis::CommandError => e
  e.message.include?('BUSYKEY')
end
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Empty hash field values preserved
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.hset('test:hash', 'empty_field', '')
@redis.hset('test:hash', 'normal_field', 'value')

dump_data = @redis.dump('test:hash')
@redis.restore('test:restored', 0, dump_data)

restored_empty = @redis.hget('test:restored', 'empty_field')
restored_empty
#=> ""

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Sorted set scores preserved through DUMP/RESTORE
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

# Simulate instance index with created timestamps as scores
@redis.zadd('test:instances', 1706000000, 'member1')
@redis.zadd('test:instances', 1706000100, 'member2')
@redis.zadd('test:instances', 1706000200, 'member3')

dump_data = @redis.dump('test:instances')
@redis.restore('test:instances:restored', 0, dump_data)

# Verify scores preserved
original = @redis.zrange('test:instances', 0, -1, with_scores: true)
restored = @redis.zrange('test:instances:restored', 0, -1, with_scores: true)

original == restored
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Set members preserved through DUMP/RESTORE
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.sadd('test:set', ['member1', 'member2', 'member3'])

dump_data = @redis.dump('test:set')
@redis.restore('test:set:restored', 0, dump_data)

original = @redis.smembers('test:set').sort
restored = @redis.smembers('test:set:restored').sort

original == restored
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## String values preserved through DUMP/RESTORE
@redis = Redis.new(host: @redis_host, port: @redis_port, db: @test_db)
@redis.flushdb

@redis.set('test:string', 'test value with spaces and special: @#$%')

dump_data = @redis.dump('test:string')
@redis.restore('test:string:restored', 0, dump_data)

original = @redis.get('test:string')
restored = @redis.get('test:string:restored')

original == restored
#=> true

## Cleanup
@redis.flushdb
@redis.close
true
#=> true

## Invalid UTF-8 in hash fields - safe_encode_hash handles correctly
load File.join(MIGRATION_DIR, 'enrich_with_original_record.rb')

enricher = OriginalRecordEnricher.allocate

# Test with invalid UTF-8 bytes
hash_with_binary = {
  'text' => 'normal text',
  'binary' => "\xFF\xFE invalid utf8".force_encoding('ASCII-8BIT')
}

encoded = enricher.send(:safe_encode_hash, hash_with_binary)

# Binary field should be wrapped in _binary key
[encoded['text'], encoded['binary'].is_a?(Hash), encoded['binary']['_binary']]
#=> ["normal text", true, "//4gaW52YWxpZCB1dGY4"]

## safe_encode_hash preserves valid UTF-8
enricher = OriginalRecordEnricher.allocate

hash_with_utf8 = {
  'text' => 'Hello World',
  'unicode' => 'Caf\u00e9 \u2603',  # Coffee snowman
  'number_as_string' => '12345'
}

encoded = enricher.send(:safe_encode_hash, hash_with_utf8)

# All fields should pass through unchanged (no _binary wrapper)
encoded.values.none? { |v| v.is_a?(Hash) && v.key?('_binary') }
#=> true

## safe_encode_hash round-trips binary data correctly
enricher = OriginalRecordEnricher.allocate

original_binary = SecureRandom.random_bytes(64)
hash_with_binary = {
  'ciphertext' => original_binary.force_encoding('ASCII-8BIT')
}

encoded = enricher.send(:safe_encode_hash, hash_with_binary)
decoded = Base64.strict_decode64(encoded['ciphertext']['_binary'])

decoded == original_binary
#=> true
