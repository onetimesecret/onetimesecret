#!/usr/bin/env ruby
# migrations/2026-01-31/05_secret_migration.rb
#
# frozen_string_literal: true

# Secret Migration: v1 -> v2
#
# Transforms Secret records for owner linkage:
# - Key pattern: unchanged (secret:{id}:object)
# - custid -> owner_id (Customer objid or 'anon')
# - original_size -> v1_original_size (deprecated field)
# - Add v1_custid for rollback
#
# CRITICAL: DO NOT touch encryption fields!
# - value_encryption: preserved exactly
# - passphrase_encryption: preserved exactly
# - value/ciphertext: preserved exactly
# - passphrase: preserved exactly
#
# Usage:
#   bundle exec ruby migrations/2026-01-31/05_secret_migration.rb           # Dry run
#   bundle exec ruby migrations/2026-01-31/05_secret_migration.rb --run     # Actual run

require 'bundler/setup'

# Only boot if running directly (not via bin/ots migrate)
unless defined?(Onetime::CLI)
  require_relative '../../lib/onetime'
  OT.boot! :app
end

require_relative 'lib/migration_helper'

module OTS
  module Migration
    class SecretMigration < Familia::Migration::Pipeline
      self.migration_id = '20260131_05_secret_migration'
      self.description = 'Migrate Secret records with owner linkage'
      self.dependencies = ['20260131_01_customer_migration']

      # Encryption fields that must NEVER be modified
      PROTECTED_FIELDS = %w[
        value value_encryption
        ciphertext
        passphrase passphrase_encryption
      ].freeze

      def prepare
        @model_class = Onetime::Secret
        @batch_size = 200  # Secrets are simpler, can batch more
        @migrated_at = Time.now.to_f.to_s

        # Build lookup mapping
        info "Building email to customer objid mapping..."
        @email_to_customer = Helper.build_email_to_customer_objid_mapping
        info "Found #{@email_to_customer.size} email->customer mappings"

        info "Total secrets: #{@model_class.instances.size}"
      end

      def migration_needed?
        # Check if any secrets have email-based custid without owner_id
        count = 0
        @model_class.instances.revrangeraw(0, 200).each do |identifier|
          secret = @model_class.load(identifier) rescue nil
          next unless secret

          # Needs migration if v1_custid is empty but has email-like custid
          if secret.v1_custid.to_s.empty?
            custid = secret.respond_to?(:custid) ? secret.custid.to_s : ''
            if custid.include?('@') || (custid != 'anon' && secret.owner_id.to_s.empty?)
              count += 1
            end
          end
        end

        info "Found #{count} secrets needing migration (sample of first 200)"
        count > 0
      end

      def should_process?(obj)
        return false unless obj

        # Skip already migrated
        if obj.v1_custid.to_s.present?
          track_stat(:skipped_already_migrated)
          return false
        end

        # Skip if owner_id already populated with valid objid
        if Helper.owner_migrated?(obj)
          track_stat(:skipped_owner_present)
          return false
        end

        true
      end

      def build_update_fields(obj)
        # Determine v1 custid
        v1_custid = obj.respond_to?(:custid) ? obj.custid.to_s : ''
        v1_custid = 'anon' if v1_custid.empty?

        # Determine new owner_id
        owner_id = if v1_custid == 'anon'
                     'anon'
                   else
                     @email_to_customer[v1_custid] || 'anon'
                   end

        if owner_id == 'anon' && v1_custid != 'anon'
          track_stat(:orphaned_to_anon)
          warn "Secret #{obj.objid[0..7]}... owner not found: #{v1_custid}"
        end

        # Handle deprecated original_size field
        v1_original_size = nil
        if obj.respond_to?(:original_size) && obj.original_size.to_s.present?
          v1_original_size = obj.original_size.to_s
          track_stat(:original_size_preserved)
        end

        track_stat(:objects_transformed)

        fields = {
          'owner_id' => owner_id,
          'v1_custid' => v1_custid,
          'v1_identifier' => v1_custid,
          'migration_status' => 'completed',
          'migrated_at' => @migrated_at,
        }

        # Preserve deprecated field if it existed
        fields['v1_original_size'] = v1_original_size if v1_original_size

        fields
      end

      def execute_update(pipe, obj, fields, original_key = nil)
        return debug("Would skip Secret b/c empty fields") unless fields&.any?

        dbkey = original_key || obj.dbkey

        # SAFETY CHECK: Ensure we're not modifying protected fields
        protected = fields.keys & PROTECTED_FIELDS
        unless protected.empty?
          error "ABORTING: Attempt to modify protected encryption fields: #{protected.join(', ')}"
          track_stat(:protected_field_violation)
          return
        end

        # Store original record for rollback
        store_original_if_needed(pipe, dbkey)

        # Apply only the safe field updates
        pipe.hmset(dbkey, *fields.flatten)

        dry_run_only? do
          debug("Would update Secret #{obj.objid[0..7]}...: #{fields.keys.join(', ')}")
        end
      end

      private

      def store_original_if_needed(pipe, dbkey)
        original_record_key = "#{dbkey}:_original_record"

        # Only store if not already present (check is approximate in pipeline)
        # The actual storage will be conditional in application logic
        original_data = {
          'key' => dbkey,
          'db' => 8,
          'exported_at' => Time.now.utc.iso8601,
          'fields_updated' => %w[owner_id v1_custid v1_identifier migration_status migrated_at],
        }

        pipe.setnx(original_record_key, original_data.to_json)
        pipe.expire(original_record_key, 86400 * 30) # 30 days retention
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(OTS::Migration::SecretMigration.cli_run)
end
