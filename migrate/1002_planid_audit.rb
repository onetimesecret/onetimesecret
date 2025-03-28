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
      run_mode_banner

      deprecated_customers = []
      empty_planid_customers = []
      unique_deprecated_plans = Hash.new(0) # Track count of each deprecated plan

      # Use Redis scan for non-blocking iteration over customer keys
      cursor = "0"
      pattern = "customer:*:object"
      batch_size = 1000
      redis_client = redis

      info "Starting scan of customer records..."

      loop do
        track_stat(:loops)

        cursor, keys = redis_client.scan(cursor, match: pattern, count: batch_size)

        keys.each do |key|
          track_stat(:total_keys)

          # Extract customer ID from key
          custid = key.split(':')[1] rescue nil
          next unless custid

          keytype = redis_client.type(key)
          debug "Customer ID: #{custid} (#{key})"
          debug "Key type: #{keytype}"

          # Get planid directly from Redis hash
          planid = redis_client.hget(key, 'planid')

          # Handle empty planid case
          if planid.nil? || planid.strip.empty?
            track_stat(:empty_count)
            empty_planid_customers << { custid: custid }
            debug "Customer #{custid} has empty planid"

            # Fix empty planid by setting to 'basic' if in actual run mode
            execute_if_actual_run do
              redis_client.hset(key, 'planid', 'basic')
              track_stat(:changed_customers)
              info "Updated customer #{custid} to 'basic' plan"
            end

            next
          end

          normalized_planid = Onetime::Plan.normalize(planid)

          # Check if plan is deprecated
          unless VALID_PLANS.include?(normalized_planid)
            track_stat(:deprecated_count)
            deprecated_customers << { custid: custid, planid: planid }
            unique_deprecated_plans[normalized_planid] += 1

            # Fix deprecated plan by updating to 'basic' if in actual run mode
            execute_if_actual_run do
              redis_client.hset(key, 'planid', 'basic')
              track_stat(:changed_customers)
              info "Updated customer #{custid} from '#{planid}' to 'basic' plan"
            end

            # Print progress for large datasets
            progress(stats[:deprecated_count], stats[:total_keys], "Found deprecated plans", batch_size)
          end
        end

        # Exit loop when scan is complete
        break if cursor == "0"
      end

      info "Total keys scanned: #{stats[:total_keys]} in #{stats[:loops]} loops"

      # Report empty planid customers
      if empty_planid_customers.empty?
        info "No customers found with empty plan IDs."
      else
        info "Found #{stats[:empty_count]} customers with empty plan IDs"
        empty_planid_customers.each do |customer|
          debug "Customer ID: #{customer[:custid]}"
        end
      end

      # Report unique deprecated plans
      if unique_deprecated_plans.empty?
        info "No deprecated plan types found."
      else
        info "Found #{unique_deprecated_plans.size} unique deprecated plan types:"
        unique_deprecated_plans.sort_by { |_, count| -count }.each do |plan_id, count|
          info "  Plan ID: #{plan_id} - #{count} customers"
        end
      end

      # Report deprecated plan customers
      if deprecated_customers.empty?
        info "No customers found on deprecated plans."
      else
        info "Found #{stats[:deprecated_count]} customers on deprecated plans:"
        deprecated_customers.each do |customer|
          debug "Customer ID: #{customer[:custid]}, Plan ID: #{customer[:planid]}"
        end
      end

      # Print summary based on run mode
      print_summary do
        if dry_run?
          # Make this message very visible
          info("Would update #{stats[:deprecated_count] + stats[:empty_count]} customers to 'basic' plan")
        else
          info("Updated #{stats[:changed_customers]} customers to 'basic' plan")
        end
      end

      true # Return success
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
