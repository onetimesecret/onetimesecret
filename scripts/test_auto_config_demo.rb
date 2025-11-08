#!/usr/bin/env ruby
#
# frozen_string_literal: true

# Demo of the new auto-configuration behavior for Docker users with minimal env vars

class MockOT
  @@conf = {
    'redis' => {
      'uri' => 'redis://localhost:6379/0',
      'dbs' => {}  # Empty = using all defaults (database 0)
    }
  }

  def self.conf
    @@conf
  end

  def self.ld(msg)
    puts "[DEBUG] #{msg}"
  end
end

# Mock the auto-configuration logic from our implementation
def apply_auto_configuration(legacy_locations)
  current_conf = MockOT.conf
  current_conf['redis']['dbs'] ||= {}

  puts "[apply_auto_configuration] Applying auto-configuration for legacy data compatibility"

  legacy_locations.each do |model, locations|
    primary_location = locations.first
    legacy_db = primary_location[:database]
    current_conf['redis']['dbs'][model] = legacy_db
    puts "[apply_auto_configuration] Configured #{model} to use database #{legacy_db}"
  end

  puts "[apply_auto_configuration] Auto-configuration complete"
end

def using_default_database_config?(current_dbs, legacy_locations)
  legacy_locations.keys.any? do |model|
    configured_db = current_dbs[model] || 0
    configured_db == 0  # Using default database 0 for a model that has legacy data
  end
end

# Simulate Case B: Docker with minimal env variables
puts "=== CASE B: Docker with Minimal Environment Variables ==="
puts "Environment: SECRET=<hidden>, REDIS_URI=redis://redis:6379/0"
puts "Configuration: Using v0.23 defaults (all models -> database 0)"

# Simulate detected legacy data
legacy_locations = {
  'session' => [{ database: 1, key_count: 500, sample_keys: ['session:abc123'] }],
  'customer' => [{ database: 6, key_count: 200, sample_keys: ['customer:user456'] }],
  'secret' => [{ database: 8, key_count: 1000, sample_keys: ['secret:xyz789'] }]
}

current_dbs = MockOT.conf.dig('redis', 'dbs') || {}
needs_auto_config = legacy_locations.any? && using_default_database_config?(current_dbs, legacy_locations)

puts "\n📊 Found existing data in legacy databases:"
legacy_locations.each do |model, locations|
  locations.each do |location|
    puts "  • #{location[:key_count]} #{model} records in database #{location[:database]}"
  end
end

puts "\nAuto-configuration needed: #{needs_auto_config}"

if needs_auto_config
  puts "\n📝 Applying auto-configuration..."
  apply_auto_configuration(legacy_locations)

  puts "\n✅ Configuration after auto-configuration:"
  puts "   redis.dbs: #{MockOT.conf['redis']['dbs']}"
  puts "\n💡 Result: Application will now connect to legacy databases"
  puts "   - Session data remains accessible in database 1"
  puts "   - Customer data remains accessible in database 6"
  puts "   - Secret data remains accessible in database 8"
  puts "   - NO DATA LOSS occurs!"
else
  puts "\n⚠️  Without auto-configuration, application would connect to database 0"
  puts "   - Legacy data in databases 1, 6, 8 would become INACCESSIBLE"
  puts "   - SILENT DATA LOSS would occur!"
end
