#!/usr/bin/env ruby

require_relative '../../support/test_helpers'

# try/initializers/detect_legacy_data_try.rb

# Mock Redis client that returns predefined responses
class MockRedisClient
  def initialize(database_data = {})
    @database_data = database_data
  end

  def ping
    "PONG"
  end

  def scan(cursor, match:, count:)
    pattern = match.gsub('*', '.*')
    regex = /^#{pattern}$/

    matching_keys = @database_data.keys.select { |key| key =~ regex }

    # Return scan response format: [new_cursor, keys_array]
    ["0", matching_keys]
  end
end

# Create test class that includes our detection methods
class LegacyDataDetector
  include Onetime::Initializers

  def initialize(mock_familia = nil)
    @mock_familia = mock_familia
  end

  # Override Familia.dbclient for testing
  def familia_dbclient(db_num)
    return MockRedisClient.new if @mock_familia.nil?

    MockRedisClient.new(@mock_familia[db_num] || {})
  end

  alias_method :original_familia_dbclient, :familia_dbclient

  # For testing, we need to override the Familia.dbclient method
  def test_detect_legacy_data(mock_redis_data, config_dbs = {})
    # Mock OT.conf to return our test configuration
    mock_conf = {
      'redis' => {
        'dbs' => config_dbs
      }
    }

    # Temporarily override OT.conf
    original_conf = OT.instance_variable_get(:@conf)
    OT.instance_variable_set(:@conf, mock_conf)

    # Mock Familia.dbclient calls
    mock_familia = mock_redis_data

    # Override the dbclient method in our detection logic
    define_singleton_method(:scan_database_for_legacy_data) do |db_num, legacy_mappings, current_dbs, legacy_locations|
      models_found = 0
      client_data = mock_familia[db_num] || {}

      legacy_mappings.each do |model_name, expected_dbs|
        current_db = current_dbs[model_name] || 0
        next if db_num == current_db

        key_pattern = "#{model_name}:*"
        pattern_regex = /^#{Regexp.escape(key_pattern).gsub('\*', '.*')}$/
        keys = client_data.keys.select { |key| key =~ pattern_regex }

        next if keys.empty?

        models_found += 1
        legacy_locations[model_name] ||= []
        legacy_locations[model_name] << {
          database: db_num,
          key_count: keys.length,
          sample_keys: keys.first(3),
          expected_database: current_db,
          was_legacy_default: expected_dbs.include?(db_num)
        }
      end

      models_found
    end

    # Skip environment variable checks for testing
    define_singleton_method(:skip_legacy_data_check?) { false }

    result = detect_legacy_data

    # Restore original configuration
    OT.instance_variable_set(:@conf, original_conf)

    result
  end
end

## Clean installation returns empty results
@mock_redis = {
  0 => {
    'session:new123' => 'data',
    'customer:user456' => 'data'
  }
}
@detector = LegacyDataDetector.new
@result = @detector.test_detect_legacy_data(@mock_redis)
@result[:legacy_locations]
#=> {}

## Detection finds legacy session data in DB 1
@mock_redis = {
  0 => {
    'session:new123' => 'data'
  },
  1 => {
    'session:legacy456' => 'session_data',
    'session:legacy789' => 'more_session_data'
  }
}
@detector = LegacyDataDetector.new
@result = @detector.test_detect_legacy_data(@mock_redis)
@result[:legacy_locations].keys
#=> ['session']

## Legacy session data shows correct details
@result[:legacy_locations]['session'].first[:database]
#=> 1

## Legacy session data shows correct key count
@result[:legacy_locations]['session'].first[:key_count]
#=> 2

## Legacy session data identifies as legacy default
@result[:legacy_locations]['session'].first[:was_legacy_default]
#=> true

## Detection finds customer data in legacy DB 6
@mock_redis = {
  0 => {},
  6 => {
    'customer:legacy123' => 'customer_data',
    'customdomain:example.com' => 'domain_data'
  }
}
@detector = LegacyDataDetector.new
result = @detector.test_detect_legacy_data(@mock_redis)
result[:legacy_locations].keys.sort
#=> ['customdomain', 'customer']

## Detection respects current configuration
@mock_redis = {
  1 => {
    'session:test123' => 'data'
  }
}
@config_dbs = { 'session' => 1 }  # Session is configured for DB 1
@detector = LegacyDataDetector.new
@result = @detector.test_detect_legacy_data(@mock_redis, @config_dbs)
@result[:legacy_locations]
#=> {}

## Detection finds metadata in legacy DB 7
@mock_redis = {
  7 => {
    'metadata:secret123' => 'metadata',
    'metadata:secret456' => 'more_metadata'
  }
}
@detector = LegacyDataDetector.new
result = @detector.test_detect_legacy_data(@mock_redis)
result[:legacy_locations]['metadata'].first[:database]
#=> 7

## Detection finds secret data in legacy DB 8
@mock_redis = {
  8 => {
    'secret:abc123' => 'encrypted_secret',
    'secret:abc456' => 'more_encrypted_secret',
  }
}
@detector = LegacyDataDetector.new
result = @detector.test_detect_legacy_data(@mock_redis)
result[:legacy_locations].keys.sort
#=> ['secret']

## Detection finds feedback in legacy DB 11
@mock_redis = {
  11 => {
    'feedback:msg123' => 'user_feedback'
  }
}
@detector = LegacyDataDetector.new
result = @detector.test_detect_legacy_data(@mock_redis)
result[:legacy_locations]['feedback'].first[:database]
#=> 11

## Multiple databases with mixed data
@mock_redis = {
  1 => {
    'session:session1' => 'data'
  },
  6 => {
    'customer:customer1' => 'data',
    'customer:customer2' => 'data'
  },
  8 => {
    'secret:secret1' => 'data'
  }
}
@detector = LegacyDataDetector.new
result = @detector.test_detect_legacy_data(@mock_redis)
result[:legacy_locations].keys.sort
#=> ['customer', 'secret', 'session']

## Sample keys are properly limited to 3
@mock_redis = {
  8 => {
    'secret:secret1' => 'data',
    'secret:secret2' => 'data',
    'secret:secret3' => 'data',
    'secret:secret4' => 'data',
    'secret:secret5' => 'data'
  }
}
@detector = LegacyDataDetector.new
result = @detector.test_detect_legacy_data(@mock_redis)
result[:legacy_locations]['secret'].first[:sample_keys].length
#=> 3

## Auto-configuration flag is set when using defaults with legacy data
@mock_redis = {
  1 => {
    'session:legacy123' => 'data'
  },
  8 => {
    'secret:legacy456' => 'data'
  }
}
@detector = LegacyDataDetector.new
@result = @detector.test_detect_legacy_data(@mock_redis)  # No explicit config = using defaults
@result[:needs_auto_config]
#=> true

## Auto-configuration flag is false when explicit config exists
@config_dbs = { 'session' => 1, 'secret' => 8 }  # Explicit configuration
@detector = LegacyDataDetector.new
@result = @detector.test_detect_legacy_data(@mock_redis, @config_dbs)
@result[:needs_auto_config]
#=> false

## Auto-configuration works with empty legacy locations
@mock_redis = { 0 => { 'session:new123' => 'data' } }
@detector = LegacyDataDetector.new
@result = @detector.test_detect_legacy_data(@mock_redis)
@result[:needs_auto_config]
#=> false
