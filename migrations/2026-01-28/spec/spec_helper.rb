# migrations/2026-01-28/spec/spec_helper.rb
#
# frozen_string_literal: true

require 'rspec'
require 'tmpdir'
require 'fileutils'
require 'json'

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Load the migration module
require 'migration'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  # Reset Migration::Config before each test
  config.before(:each) do
    Migration::Config.reset!
  end

  # Reset schema registry before each test
  config.before(:each) do
    Migration::Schemas.reset!
  end
end

# Helper module for Redis availability check
module RedisTestHelper
  def self.redis_available?
    return @redis_available unless @redis_available.nil?

    @redis_available = begin
      redis = Redis.new(url: 'redis://127.0.0.1:6379/15')
      redis.ping
      redis.close
      true
    rescue StandardError
      false
    end
  end

  def self.skip_unless_redis_available
    skip 'Redis not available' unless redis_available?
  end
end

# Helper module for temporary directory management
module TempDirHelper
  def create_temp_dir
    Dir.mktmpdir('kiba_migration_test')
  end

  def with_temp_dir
    dir = create_temp_dir
    yield dir
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exist?(dir)
  end
end

# Helper module for JSONL file operations
module JsonlFileHelper
  def write_jsonl(path, records)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w') do |f|
      records.each { |r| f.puts(JSON.generate(r)) }
    end
  end

  def read_jsonl(path)
    return [] unless File.exist?(path)
    File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true) }
  end

  def read_json(path)
    return nil unless File.exist?(path)
    JSON.parse(File.read(path))
  end
end
