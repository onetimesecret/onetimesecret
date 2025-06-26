#!/usr/bin/env ruby
# migrate/1512_customer_objid.rb
#
# Customer Object ID and User Type Migration
#
# Purpose: Populates objid and user_type fields for all existing Customer records.
# - objid: Set to the customer's custid value
# - user_type: Set to 'authenticated' (default user type)
#
# Usage:
#   ruby migrate/1512_customer_objid.rb --dry-run  # Preview changes
#   ruby migrate/1512_customer_objid.rb --run      # Execute migration
#
#   bin/ots migrate 1512_customer_objid.rb

base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(base_path, 'lib')

require 'onetime'
require 'onetime/migration'

require 'onetime/refinements/uuidv7_refinements'

MODEL_KLASS = V2::Customer

module Onetime
  class Migration < BaseMigration
    using Onetime::UUIDv7Refinements

    def prepare
      info("[1512_customer_objid] Preparing customer objid and user_type migration")

      # Get total customer count using Familia::SortedSet
      @total_customers = MODEL_KLASS.values.size
      @redis_client = MODEL_KLASS.redis
      @scan_pattern = "#{MODEL_KLASS.prefix}:*:object"
      @batch_size = 1000

      # Initialize counters
      @total_scanned = 0
      @customers_needing_update = 0
      @customers_updated = 0
      @error_count = 0

      info("Redis connection: #{@redis_client.connection[:id]}")
      info("Scan pattern: #{@scan_pattern}")
      info("Total customers in system: #{@total_customers}")
      info("Batch size: #{@batch_size}")

      # Test Redis connection
      begin
        @redis_client.ping
        debug("Redis connection verified")
      rescue => ex
        error("Cannot connect to Redis: #{ex.message}")
        raise ex
      end
    end

    def migration_needed?
      info("[1512_customer_objid] Checking if migration is needed...")

      # We want to run always so that if there is an error or issue we can run
      # again. NOTE: B/c of the idempotent expectation, we are careful to not
      # re-generate objid values. If there is one set, we will use that
      # otherwise each run, each customer would have a different ID.
      true
    end

    def migration_not_needed_banner
      info <<~HEREDOC

        #{separator}
        Migration not needed. This usually means:

          1. All customer records already have objid and user_type fields
          2. The migration has already been successfully applied
          3. There are no customer records in the system

        To verify customer record status:
          $ bin/ots console
          > MODEL_KLASS.values.size
          > customer = MODEL_KLASS.load('some_customer_id')
          > customer.objid
          > customer.user_type

        #{separator}
      HEREDOC
    end

    def migrate
      run_mode_banner

      info("[1512_customer_objid] Starting customer objid and user_type migration")
      info("Processing up to #{@total_customers} customer records")

      cursor = "0"

      loop do
        cursor, keys = @redis_client.scan(cursor, match: @scan_pattern, count: @batch_size)
        @total_scanned += keys.size

        progress(@total_scanned, @total_customers, "Scanning customers") if @total_scanned % 500 == 0

        keys.each do |key|
          process_customer_record(key)
        end

        break if cursor == "0"
      end

      print_summary do
        info("Total customers scanned: #{@total_scanned}")
        info("Customers needing update: #{@customers_needing_update}")
        info("Customers updated: #{@customers_updated}")
        info("Errors encountered: #{@error_count}")

        if @error_count > 0
          info("Check logs for error details")
        end

        if dry_run? && @customers_needing_update > 0
          info("Run with --run to apply these updates")
        end
      end

      @error_count == 0
    end

    private

    def process_customer_record(key)
      begin
        record_data = @redis_client.hgetall(key)
        custid = record_data['custid']

        if custid.to_s.empty?
          debug("Skipping #{key} (empty custid)")
          track_stat(:skipped_empty_custid)
          return
        end

        # Check current field values
        current_created = record_data['created']
        current_objid = record_data['objid']
        current_user_type = record_data['user_type']
        email = record_data['email']

        needs_objid = current_objid.to_s.empty? || true
        needs_user_type = current_user_type.to_s.empty?

        return unless needs_objid || needs_user_type

        @customers_needing_update += 1
        unique_objid = current_objid || SecureRandom.uuid_v7_from(current_created)
        unique_extid = OT::Utils.secure_shorten_id(Digest::SHA256.hexdigest(unique_objid))

        # Log what we're about to update
        updates = []
        if needs_objid
          updates << "objid:#{unique_objid} extid: #{unique_extid} custid=#{custid}"
        end
        updates << "user_type=authenticated" if needs_user_type

        info("Customer (#{current_created}): #{updates.join(', ')}")

        # Apply updates if in actual run mode
        for_realsies_this_time? do
          update_fields = {}
          update_fields['objid'] = unique_objid if needs_objid
          update_fields['extid'] = unique_extid if needs_objid
          update_fields['user_type'] = 'authenticated' if needs_user_type

          @redis_client.hmset(key, *update_fields.to_a.flatten)
          @customers_updated += 1
          track_stat(:customers_updated)
          track_stat(:objid_set) if needs_objid
          track_stat(:user_type_set) if needs_user_type
        end

      rescue => ex
        @error_count += 1
        error("Error processing #{key}: #{ex.message}")
        track_stat(:errors)
      end
    end

    def separator
      '-' * 60
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
