#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick verification that the migration library loads correctly.
# Run: ruby lib/test_lib.rb

require_relative 'migration'

puts "Migration Library v#{Migration::VERSION}"
puts

# Test LookupRegistry
puts "Testing LookupRegistry..."
registry = Migration::LookupRegistry.new(results_dir: '/tmp/test_results')
registry.register(:test_lookup, { 'foo' => 'bar' }, phase: 1)
raise "Register failed" unless registry.lookup(:test_lookup, 'foo') == 'bar'
raise "Loaded check failed" unless registry.loaded?(:test_lookup)
puts "  LookupRegistry: OK"

# Test RedisHelper (without connecting)
puts "Testing RedisHelper..."
helper = Migration::RedisHelper.new(redis_url: 'redis://localhost:6379', temp_db: 15)
raise "RedisHelper init failed" unless helper.redis_url == 'redis://localhost:6379'
raise "RedisHelper temp_db failed" unless helper.temp_db == 15
puts "  RedisHelper: OK (no connection test)"

# Test PhaseManifest
puts "Testing PhaseManifest..."
manifest = Migration::PhaseManifest.new(results_dir: '/tmp/test_results')
raise "Manifest init failed" unless manifest.results_dir == '/tmp/test_results'
raise "Phase complete check failed" if manifest.phase_complete?(1)
puts "  PhaseManifest: OK"

# Test TransformerBase (create minimal subclass)
puts "Testing TransformerBase..."
class TestTransformer < Migration::TransformerBase
  PHASE = 99
  MODEL_NAME = 'test'

  def process_record(record)
    []
  end
end
transformer = TestTransformer.new
raise "TransformerBase init failed" unless transformer.is_a?(Migration::TransformerBase)
puts "  TransformerBase: OK"

puts
puts "All tests passed."
