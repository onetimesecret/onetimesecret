#!/usr/bin/env ruby

require 'redis'

# Connect to redis db 6
redis = Redis.new(db: 6)

# Track counts
total_count = 0
domain_mappings = {}

# Use scan to iterate through keys matching customdomain:*:object
# This is more efficient than using KEYS for large datasets
cursor = "0"
pattern = "customdomain:*:object"

puts "Starting population of display_domains hash..."
puts "Scanning for keys matching pattern: #{pattern}"

begin
  # First pass: collect all display_domains and their IDs
  loop do
    cursor, keys = redis.scan(cursor, match: pattern, count: 1000)

    keys.each do |key|
      total_count += 1
      display_domain = redis.hget(key, "display_domain")
      domain_id = redis.hget(key, "domainid")

      if display_domain && domain_id
        domain_mappings[display_domain] = domain_id
        puts "Found mapping: #{display_domain} -> #{domain_id}"
      else
        puts "Warning: Missing data for #{key} (display_domain: #{display_domain}, domainid: #{domain_id})"
      end
    end

    # Break when we've gone through all keys
    break if cursor == "0"
  end

  puts "\nFound #{domain_mappings.length} domain mappings"
  puts "Beginning atomic update..."

  # Second pass: add all mappings in a single transaction
  redis.multi do |multi|
    # First delete any existing hash to ensure clean state
    multi.del("customdomain:display_domains")

    # Add all mappings to the hash
    domain_mappings.each do |display_domain, domain_id|
      # NOTE: We're using hsetnx to not overwrite existing mappings
      multi.hsetnx("customdomain:display_domains", display_domain, domain_id)
    end
  end

  # Verify the hash size
  hash_size = redis.hlen("customdomain:display_domains")
  puts "\nPopulation complete!"
  puts "Processed #{total_count} custom domain records"
  puts "Added #{domain_mappings.length} mappings to the hash"
  puts "display_domains hash now contains #{hash_size} mappings"

  # Optional: Print first few mappings as verification
  if hash_size > 0
    puts "\nSample mappings:"
    redis.hscan_each("customdomain:display_domains", count: 5).take(5).each do |domain, id|
      puts "  #{domain} -> #{id}"
    end
  end

rescue Redis::CommandError => e
  puts "Redis error: #{e.message}"
  exit 1
rescue => e
  puts "Unexpected error: #{e.message}"
  exit 1
end
