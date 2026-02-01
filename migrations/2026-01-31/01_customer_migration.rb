#!/usr/bin/env ruby
# migrations/2026-01-31/01_customer_migration.rb
#
# frozen_string_literal: true

# Customer Migration: v1 -> v2
#
# Transforms Customer records from email-keyed to UUID-keyed format:
# - Key pattern: customer:{email}:object -> customer:{objid}:object
# - custid: email -> objid (UUID)
# - Add extid with format 'ur%<id>s'
# - Preserve original custid in v1_custid field
# - Migrate billing fields to Organization (separate step)
#
# Usage:
#   bundle exec ruby migrations/2026-01-31/01_customer_migration.rb           # Dry run
#   bundle exec ruby migrations/2026-01-31/01_customer_migration.rb --run     # Actual run

require 'bundler/setup'
require 'familia/migration'

# Only boot if running directly (not via bin/ots migrate)
unless defined?(Onetime::CLI)
  require_relative '../../lib/onetime'
  OT.boot! :app
end

require_relative 'lib/migration_helper'

module OTS
  module Migration
    class CustomerMigration < Familia::Migration::Pipeline
      self.migration_id = '20260131_01_customer_migration'
      self.description = 'Migrate Customer records from email-keyed to UUID-keyed format'
      self.dependencies = []

      def prepare
        @model_class = Onetime::Customer
        @batch_size = 100
        @migrated_at = Time.now.to_f.to_s

        # Track keys that need renaming (old_key -> new_key)
        @key_renames = {}

        info "Preparing Customer migration..."
        info "Total customers in instances index: #{@model_class.instances.size}"
      end

      def migration_needed?
        p [:PLOPPLOP]
        # Check if any customers still have email-based custid (v1 pattern)
        count = 0
        @model_class.instances.each do |dbkey|
          cust = @model_class.find_by_key(dbkey)
          next unless cust

          # v1 pattern: custid contains @ (email address)
          if cust.custid.to_s.include?('@') && cust.v1_custid.to_s.empty?
            count += 1
          end
        end

        info "Found #{count} customers needing migration (sample of first 100)"
        count > 0
      end

      def should_process?(obj)
        return false unless obj

        # Skip anonymous users
        if obj.anonymous?
          track_stat(:skipped_anonymous)
          return false
        end

        # Skip already migrated (v1_custid populated means migration done)
        if obj.v1_custid.to_s.present?
          track_stat(:skipped_already_migrated)
          return false
        end

        # Only migrate if custid looks like v1 (email format)
        unless obj.custid.to_s.include?('@')
          track_stat(:skipped_non_email_custid)
          return false
        end

        true
      end

      def build_update_fields(obj)
        email = obj.custid.to_s
        created = obj.created.to_f

        # Generate objid from created timestamp for deterministic migration
        # The ObjectIdentifier feature should have already set objid, but
        # if custid was the identifier field, we need to handle this carefully
        new_objid = obj.objid.to_s
        if new_objid.empty? || new_objid == email
          new_objid = Helper.generate_uuid_v7_from_timestamp(created)
        end

        # Generate extid from objid
        new_extid = Helper.format_extid(new_objid, 'ur')

        track_stat(:objects_transformed)

        {
          # Core identity updates
          'objid' => new_objid,
          'extid' => new_extid,
          'custid' => new_objid,  # custid now equals objid (UUID)
          'email' => email,       # Email preserved in dedicated field

          # Migration tracking
          'v1_custid' => email,
          'v1_identifier' => email,
          'migration_status' => 'completed',
          'migrated_at' => @migrated_at,
        }
      end

      def execute_update(pipe, obj, fields, original_key = nil)
        return debug("Would skip Customer b/c empty fields") unless fields&.any?

        email = obj.custid.to_s
        new_objid = fields['objid']
        old_key = original_key || obj.dbkey
        new_key = "#{@model_class.prefix}:#{new_objid}:object"

        # Don't rename if keys are the same
        if old_key == new_key
          # Just update fields in place
          pipe.hmset(old_key, *fields.flatten)
          debug("Updated Customer in place: #{new_objid}")
        else
          # Store the complete original record before migration
          store_original_if_needed(pipe, obj, old_key)

          # Key rename: copy data to new key, update fields, mark old for cleanup
          # We use COPY (Redis 6.2+) or DUMP/RESTORE pattern
          pipe.hmset(new_key, *fields.flatten)

          # Mark old key for later cleanup (add expiration or delete)
          # For safety, we set a TTL rather than immediate delete
          pipe.expire(old_key, 86400 * 7) # 7 days grace period

          @key_renames[old_key] = new_key
          debug("Renamed Customer: #{email} -> #{new_objid}")
        end

        track_stat(:keys_renamed) if old_key != new_key

        dry_run_only? do
          debug("Would update Customer: #{fields.keys.join(', ')}")
        end
      end

      private

      def store_original_if_needed(pipe, obj, original_key)
        # Store original record for rollback capability
        return if obj._original_record.value

        original_data = {
          'object' => obj.to_h,
          'key' => original_key,
          'db' => 6,
          'exported_at' => Time.now.utc.iso8601,
        }

        original_record_key = "#{original_key}:_original_record"
        pipe.set(original_record_key, original_data.to_json)
        pipe.expire(original_record_key, 86400 * 30) # 30 days retention
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(OTS::Migration::CustomerMigration.cli_run)
end
