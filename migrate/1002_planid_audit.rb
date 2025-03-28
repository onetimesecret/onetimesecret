#!/usr/bin/env ruby
# migrate/1002_planid_audit.rb

base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(base_path, 'lib')

require 'onetime'
require 'onetime/migration'

# Set of valid plan IDs
VALID_PLANS = ['anonymous', 'basic', 'identity'].freeze

module Onetime
  class Migration < BaseMigration
    def migrate
      deprecated_count = 0
      empty_count = 0
      total_keys_count = 0
      loops_count = 0
      deprecated_customers = []
      empty_planid_customers = []

      # Use Redis scan for non-blocking iteration over customer keys
      cursor = "0"
      pattern = "customer:*:object"
      batch_size = 1000
      redis = Familia.redis(6)

      OT.li "Starting scan of customer records..."

      loop do
        loops_count += 1

        cursor, keys = redis.scan(cursor, match: pattern, count: batch_size)

        keys.each do |key|
          total_keys_count += 1

          # Extract customer ID from key
          custid = key.split(':')[1] rescue nil
          next unless custid

          keytype = redis.type(key)
          OT.ld "Customer ID: #{custid} (#{key})"
          OT.ld "Key type: #{keytype}"

          # Get planid directly from Redis hash
          planid = redis.hget(key, 'planid')

          # Handle empty planid case
          if planid.nil? || planid.strip.empty?
            empty_count += 1
            empty_planid_customers << { custid: custid }
            OT.ld "Customer #{custid} has empty planid"
            next
          end

          # Check if plan is deprecated
          unless VALID_PLANS.include?(Onetime::Plan.normalize(planid))
            deprecated_count += 1
            deprecated_customers << { custid: custid, planid: planid }

            # Print progress for large datasets
            OT.li "Found #{deprecated_count} deprecated plans..." if deprecated_count % batch_size == 0
          end
        end

        # Exit loop when scan is complete
        break if cursor == "0"
      end

      OT.li "Total keys scanned: #{total_keys_count} in #{loops_count} loops"

      # Report empty planid customers
      if empty_planid_customers.empty?
        OT.li "No customers found with empty plan IDs."
      else
        OT.li "Found #{empty_count} customers with empty plan IDs"
        empty_planid_customers.each do |customer|
          OT.ld "Customer ID: #{customer[:custid]}"
        end
      end

      # Report deprecated plan customers
      if deprecated_customers.empty?
        OT.li "No customers found on deprecated plans."
      else
        OT.li "Found #{deprecated_count} customers on deprecated plans:"
        deprecated_customers.each do |customer|
          OT.ld "Customer ID: #{customer[:custid]}, Plan ID: #{customer[:planid]}"
        end
      end
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run ? 0 : 1)
end
