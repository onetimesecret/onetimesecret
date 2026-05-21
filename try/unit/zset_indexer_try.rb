# try/unit/zset_indexer_try.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Services::ZsetIndexer
#
# Coverage:
#   - parse_score: v1 bare string, v2 JSON-quoted, nil, empty, garbage
#   - resolve_score: :skip, :default, :fallback_field policies
#   - constructor validation
#   - integration: real Redis round-trip for scored/missing/fallback paths
#
# Integration tests require a running Redis instance (VALKEY_URL or REDIS_URL).
# They are skipped gracefully when no Redis is reachable.

$LOAD_PATH.unshift(File.join(__dir__, '..', '..', 'lib'))
require 'onetime/services/zset_indexer'

# ---------------------------------------------------------------------------
# Helpers — expose private methods for white-box unit tests
# ---------------------------------------------------------------------------

class TestableIndexer < Onetime::Services::ZsetIndexer
  public :parse_score, :resolve_score
end

REDIS_URL = ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://localhost:6379/15'

def redis_available?
  r = Redis.new(url: REDIS_URL, connect_timeout: 1, read_timeout: 1)
  r.ping == 'PONG'
rescue StandardError
  false
ensure
  r&.close
end

# ---------------------------------------------------------------------------
# parse_score: v1 bare integer string
# ---------------------------------------------------------------------------

@indexer = TestableIndexer.new(
  redis_url:       REDIS_URL,
  model_prefix:    'customer',
  field_name:      'updated',
  output_zset_key: 'test:zset_indexer:by_updated',
)

## parse_score handles v1 bare integer string
@indexer.parse_score('1735689600')
#=> 1735689600

## parse_score handles v2 JSON-quoted integer string
@indexer.parse_score('"1735689600"')
#=> 1735689600

## parse_score returns nil for nil input
@indexer.parse_score(nil)
#=> nil

## parse_score returns nil for empty string
@indexer.parse_score('')
#=> nil

## parse_score returns nil for non-numeric garbage
@indexer.parse_score('not-a-number')
#=> nil

## parse_score returns nil for a JSON-quoted non-numeric string
@indexer.parse_score('"not-a-number"')
#=> nil

## parse_score handles float-ish strings (truncates to Integer)
@indexer.parse_score('1735689600.9')
#=> 1735689600

# ---------------------------------------------------------------------------
# resolve_score: :skip policy
# ---------------------------------------------------------------------------

## resolve_score with :skip and both fields nil returns nil
@indexer.resolve_score(nil, nil, 'customer:x@x.com:object')
#=> nil

## resolve_score with :skip and a valid primary returns the score
@indexer.resolve_score('1735689600', nil, 'customer:x@x.com:object')
#=> 1735689600

# ---------------------------------------------------------------------------
# resolve_score: :default policy
# ---------------------------------------------------------------------------

## resolve_score with :default and nil primary returns default_score
@default_indexer = TestableIndexer.new(
  redis_url: REDIS_URL, model_prefix: 'customer', field_name: 'updated',
  output_zset_key: 'test:zset_indexer:by_updated', on_missing: :default, default_score: 0,
)
@default_indexer.resolve_score(nil, nil, 'customer:x@x.com:object')
#=> 0

## resolve_score with :default and valid primary still returns the parsed score
@default_indexer2 = TestableIndexer.new(
  redis_url: REDIS_URL, model_prefix: 'customer', field_name: 'updated',
  output_zset_key: 'test:zset_indexer:by_updated', on_missing: :default, default_score: 0,
)
@default_indexer2.resolve_score('"1700000000"', nil, 'customer:x@x.com:object')
#=> 1700000000

# ---------------------------------------------------------------------------
# resolve_score: :fallback_field policy
# ---------------------------------------------------------------------------

## resolve_score with :fallback_field uses fallback when primary is nil
@fb_indexer = TestableIndexer.new(
  redis_url: REDIS_URL, model_prefix: 'customer', field_name: 'updated',
  output_zset_key: 'test:zset_indexer:by_updated', on_missing: :fallback_field, fallback_field: 'created',
)
@fb_indexer.resolve_score(nil, '1600000000', 'customer:x@x.com:object')
#=> 1600000000

## resolve_score with :fallback_field returns nil when both primary and fallback are nil
@fb_indexer2 = TestableIndexer.new(
  redis_url: REDIS_URL, model_prefix: 'customer', field_name: 'updated',
  output_zset_key: 'test:zset_indexer:by_updated', on_missing: :fallback_field, fallback_field: 'created',
)
@fb_indexer2.resolve_score(nil, nil, 'customer:x@x.com:object')
#=> nil

## resolve_score with :fallback_field uses primary when it is present (ignores fallback)
@fb_indexer3 = TestableIndexer.new(
  redis_url: REDIS_URL, model_prefix: 'customer', field_name: 'updated',
  output_zset_key: 'test:zset_indexer:by_updated', on_missing: :fallback_field, fallback_field: 'created',
)
@fb_indexer3.resolve_score('1735689600', '1600000000', 'customer:x@x.com:object')
#=> 1735689600

# ---------------------------------------------------------------------------
# Constructor validation
# ---------------------------------------------------------------------------

## raises on unknown on_missing policy
begin
  TestableIndexer.new(
    redis_url: REDIS_URL, model_prefix: 'x', field_name: 'f',
    output_zset_key: 'x:out', on_missing: :bogus,
  )
rescue ArgumentError => e
  e.message
end
#=~> /on_missing must be/

## raises when on_missing: :fallback_field without fallback_field
begin
  TestableIndexer.new(
    redis_url: REDIS_URL, model_prefix: 'x', field_name: 'f',
    output_zset_key: 'x:out', on_missing: :fallback_field,
  )
rescue ArgumentError => e
  e.message
end
#=~> /fallback_field/

# ---------------------------------------------------------------------------
# Integration: real Redis
# ---------------------------------------------------------------------------

if redis_available?
  @redis = Redis.new(url: REDIS_URL, connect_timeout: 2, read_timeout: 5)

  # Seed test keys
  @redis.hset('customer:alice@example.com:object', 'updated', '1735689600', 'created', '1700000000')
  @redis.hset('customer:bob@example.com:object',   'updated', '1735689100', 'created', '1699000000')
  @redis.hset('customer:noupdate@example.com:object', 'created', '1698000000')  # missing updated
  @redis.del('test:zset_indexer:by_updated')

  @int_indexer = Onetime::Services::ZsetIndexer.new(
    redis_url:       REDIS_URL,
    model_prefix:    'customer',
    field_name:      'updated',
    output_zset_key: 'test:zset_indexer:by_updated',
    on_missing:      :skip,
    scan_count:      10,
    batch_size:      10,
  )

  ## integration: dry-run scores keys without writing to Redis
  @dry_result = @int_indexer.run(execute: false)
  @redis.exists?('test:zset_indexer:by_updated')
  #=> false

  ## integration: dry-run stats.scanned covers all matching keys
  @dry_result[:scanned] >= 2
  #==> true

  ## integration: execute: true writes keys to output zset
  @int_indexer2 = Onetime::Services::ZsetIndexer.new(
    redis_url:       REDIS_URL,
    model_prefix:    'customer',
    field_name:      'updated',
    output_zset_key: 'test:zset_indexer:by_updated',
    on_missing:      :skip,
    scan_count:      10,
    batch_size:      10,
  )
  @exec_result = @int_indexer2.run(execute: true)
  @redis.zscore('test:zset_indexer:by_updated', 'customer:alice@example.com:object').to_i
  #=> 1735689600

  ## integration: missing primary field with :skip does not appear in zset
  @redis.zscore('test:zset_indexer:by_updated', 'customer:noupdate@example.com:object')
  #=> nil

  ## integration: re-run is idempotent (same score, no error)
  @int_indexer2.run(execute: true)
  @redis.zscore('test:zset_indexer:by_updated', 'customer:alice@example.com:object').to_i
  #=> 1735689600

  ## integration: fallback_field policy scores keys missing primary via created
  @redis.del('test:zset_indexer:by_updated_fb')
  @fb_int_indexer = Onetime::Services::ZsetIndexer.new(
    redis_url:       REDIS_URL,
    model_prefix:    'customer',
    field_name:      'updated',
    output_zset_key: 'test:zset_indexer:by_updated_fb',
    on_missing:      :fallback_field,
    fallback_field:  'created',
    scan_count:      10,
    batch_size:      10,
  )
  @fb_int_indexer.run(execute: true)
  @redis.zscore('test:zset_indexer:by_updated_fb', 'customer:noupdate@example.com:object').to_i
  #=> 1698000000

  # Teardown
  @redis.del(
    'customer:alice@example.com:object',
    'customer:bob@example.com:object',
    'customer:noupdate@example.com:object',
    'test:zset_indexer:by_updated',
    'test:zset_indexer:by_updated_fb',
  )
  @redis.close
else
  ## integration tests skipped — no Redis available at #{REDIS_URL}
  :skipped
  #=> :skipped
end
