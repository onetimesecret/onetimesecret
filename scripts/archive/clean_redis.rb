#!/usr/bin/env ruby
# support/clean_redis.rb
#
# Clear Redis databases with safety checks and options
#
# Usage:
#   ruby support/clean_redis.rb [options]
#
# Options:
#   --db N          Clear specific database number (default: current config)
#   --all           Clear all databases (0-15)
#   --pattern GLOB  Only clear keys matching pattern
#   --dry-run       Show what would be deleted without actually deleting
#   --force         Skip confirmation prompts
#   --env ENV       Use specific environment config
#
#   # Clear current database (dry run first). These are equivalent
#   # because dry-run is the default behaviour.
#   $ ruby support/clean_redis.rb --dry-run
#
#   # Clear current database
#   $ ruby support/clean_redis.rb --force
#
#   # Clear specific database
#   $ ruby support/clean_redis.rb --db 1 --force
#
#   # Clear all databases
#   $ ruby support/clean_redis.rb --all --force
#
#   # Clear only OneTimeSecret keys
#   $ ruby support/clean_redis.rb --pattern "onetime:*" --force
#
#   # Clear mutable settings keys only
#   $ ruby support/clean_redis.rb --pattern "*colonelconfig*" --force
#
#   # Clear test environment
#   $ ruby support/clean_redis.rb --env test --force
#

require 'redis'
require 'optparse'

class RedisCleaner
  attr_reader :options

  def initialize
    @options = {
      db: nil,
      all: false,
      pattern: '*',
      dry_run: false,
      force: false,
      env: ENV['RACK_ENV'] || 'development',
    }

    parse_options
    @redis_config = load_redis_config
  end

  def run
    puts "Redis Cleaner - Environment: #{@options[:env]}"
    puts "Redis Config: #{@redis_config}"
    puts

    if @options[:all]
      clear_all_databases
    else
      clear_single_database(@options[:db] || @redis_config[:db] || 0)
    end
  end

  private

  def parse_options
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"

      opts.on('--db N', Integer, 'Clear specific database number') do |db|
        @options[:db] = db
      end

      opts.on('--all', 'Clear all databases (0-15)') do
        @options[:all] = true
      end

      opts.on('--pattern PATTERN', 'Only clear keys matching pattern') do |pattern|
        @options[:pattern] = pattern
      end

      opts.on('--dry-run', 'Show what would be deleted') do
        @options[:dry_run] = true
      end

      opts.on('--force', 'Skip confirmation prompts') do
        @options[:force] = true
      end

      opts.on('--env ENV', 'Use specific environment') do |env|
        @options[:env] = env
      end

      opts.on('-h', '--help', 'Show this help') do
        puts opts
        exit
      end
    end.parse!
  end

  def load_redis_config
    redis_url = ENV['REDIS_URL']

    if redis_url
      # Parse REDIS_URL (e.g., redis://localhost:6379/0)
      uri = URI.parse(redis_url)
      return {
        host: uri.host || 'localhost',
        port: uri.port || 6379,
        db: uri.path ? uri.path[1..-1].to_i : 0,
      }
    end

    # Fallback to individual environment variables or defaults
    {
      host: ENV['REDIS_HOST'] || 'localhost',
      port: (ENV['REDIS_PORT'] || 6379).to_i,
      db: (ENV['REDIS_DB'] || 0).to_i,
    }
  end

  def clear_all_databases
    (0..15).each do |db_num|
      clear_single_database(db_num)
    end
  end

  def clear_single_database(db_num)
    redis = connect_to_db(db_num)

    keys = redis.keys(@options[:pattern])

    puts "Database #{db_num}:"
    puts "  Keys matching '#{@options[:pattern]}': #{keys.length}"

    if keys.empty?
      puts "  No keys to clear"
      return
    end

    if @options[:dry_run]
      puts "  DRY RUN - Would delete:"
      keys.each { |key| puts "    #{key}" }
      return
    end

    unless @options[:force]
      print "  Delete #{keys.length} keys from database #{db_num}? (y/N): "
      response = $stdin.gets.chomp.downcase
      return unless ['y', 'yes'].include?(response)
    end

    if @options[:pattern] == '*'
      # More efficient for clearing entire database
      redis.flushdb
      puts "  Flushed entire database"
    else
      # Delete specific keys
      deleted = 0
      keys.each_slice(1000) do |key_batch|
        deleted += redis.del(*key_batch)
      end
      puts "  Deleted #{deleted} keys"
    end

  rescue Redis::CannotConnectError => e
    puts "  Cannot connect to Redis: #{e.message}"
  rescue => e
    puts "  Error: #{e.message}"
  ensure
    redis&.quit
  end

  def connect_to_db(db_num)
    Redis.new(
      host: @redis_config[:host],
      port: @redis_config[:port],
      db: db_num,
      timeout: 5,
    )
  end
end

# Run the cleaner if called directly
if __FILE__ == $0
  RedisCleaner.new.run
end
