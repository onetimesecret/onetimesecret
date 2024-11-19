#!/usr/bin/env ruby

# Migration: Populate Display Domains
# =================================
#
# This migration script populates the display_domains hash in Redis with mappings
# between display domains and their corresponding domain IDs. This is used to
# efficiently look up domain IDs by their display domain without having to scan
# through all domain objects.
#
# Usage
# -----
#
# This migration can be run in two ways:
#
# 1. Via the CLI command:
#    ```
#    bin/ots migrate 816_populate_display_domains.rb
#    ```
#
# 2. Directly:
#    ```
#    ./migrate/816_populate_display_domains.rb
#    ```
#
# Technical Details
# ----------------
#
# - Redis Database: Uses DB 6 (accessed via Familia.redis)
# - Key Pattern: Scans for keys matching 'customdomain:*:object'
# - Hash Fields: Extracts 'display_domain' and 'domainid' from each domain object
# - Target Hash: Stores mappings in 'customdomain:display_domains'
#
# Safety Measures
# --------------
#
# - Uses SCAN instead of KEYS for better performance on large datasets
# - Processes keys in batches of 1000
# - Uses atomic transaction for final update
# - Validates results after completion

base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(base_path, 'lib')

require 'onetime'
require 'onetime/migration'

module Onetime
  class Migration < BaseMigration
    def migrate
      # Track counts
      total_count = 0
      domain_mappings = {}

      # Use scan to iterate through keys matching customdomain:*:object
      cursor = "0"
      pattern = "customdomain:*:object"

      log "Starting population of display_domains hash..."
      log "Scanning for keys matching pattern: #{pattern}"

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
              log "Found mapping: #{display_domain} -> #{domain_id}"
            else
              log "Warning: Missing data for #{key} (display_domain: #{display_domain}, domainid: #{domain_id})"
            end
          end

          # Break when we've gone through all keys
          break if cursor == "0"
        end

        log "\nFound #{domain_mappings.length} domain mappings"
        log "Beginning atomic update..."

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
        log "\nPopulation complete!"
        log "Processed #{total_count} custom domain records"
        log "Added #{domain_mappings.length} mappings to the hash"
        log "display_domains hash now contains #{hash_size} mappings"

        # Optional: Print first few mappings as verification
        if hash_size > 0
          log "\nSample mappings:"
          redis.hscan_each("customdomain:display_domains", count: 5).take(5).each do |domain, id|
            log "  #{domain} -> #{id}"
          end
        end

        true
      rescue Redis::CommandError => e
        log "Redis error: #{e.message}"
        false
      rescue => e
        log "Unexpected error: #{e.message}"
        log e.backtrace if OT.debug?
        false
      end
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run ? 0 : 1)
end
