#!/usr/bin/env ruby

require 'redis'

# Connect to redis db 6
redis = Redis.new(db: 6)

# Track counts
total_count = 0
display_domains = []

# Use scan to iterate through keys matching customdomain:*:object
# This is more efficient than using KEYS for large datasets
cursor = "0"
pattern = "customdomain:*:object"

puts "Starting population of display_domains set..."
puts "Scanning for keys matching pattern: #{pattern}"

begin
  # First pass: collect all display_domains
  loop do
    cursor, keys = redis.scan(cursor, match: pattern, count: 1000)

    keys.each do |key|
      total_count += 1
      display_domain = redis.hget(key, "display_domain")

      if display_domain
        display_domains << display_domain
        puts "Found display_domain: #{display_domain}"
      else
        puts "Warning: No display_domain found for #{key}"
      end
    end

    # Break when we've gone through all keys
    break if cursor == "0"
  end

  puts "\nFound #{display_domains.length} display domains"
  puts "Beginning atomic update..."

  # Second pass: add all domains in a single transaction
  redis.multi do |multi|
    display_domains.each do |domain|
      multi.sadd("customdomain:display_domains", domain)
    end
  end

  # Verify the set size
  set_size = redis.scard("customdomain:display_domains")
  puts "\nPopulation complete!"
  puts "Processed #{total_count} custom domain records"
  puts "Added #{display_domains.length} domains to the set"
  puts "display_domains set now contains #{set_size} domains"

rescue Redis::CommandError => e
  puts "Redis error: #{e.message}"
  exit 1
rescue => e
  puts "Unexpected error: #{e.message}"
  exit 1
end
