#!/usr/bin/env ruby
# migrations/2026-01-31/04_receipt_migration.rb
#
# frozen_string_literal: true

# Receipt Migration: v1 Metadata -> v2 Receipt
#
# Transforms Metadata records to Receipt format:
# - Key pattern: metadata:{id}:object -> receipt:{objid}:object
# - custid -> owner_id (Customer objid or 'anon')
# - Add org_id, domain_id for context
# - Field renames: viewed -> previewed, received -> revealed
# - Add v1_key, v1_custid for rollback
#
# NOTE: This is the most complex migration due to model rename.
# The old 'metadata' prefix keys need to be transformed to 'receipt' prefix.
#
# Usage:
#   bundle exec ruby migrations/2026-01-31/04_receipt_migration.rb           # Dry run
#   bundle exec ruby migrations/2026-01-31/04_receipt_migration.rb --run     # Actual run

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
    class ReceiptMigration < Familia::Migration::Model
      self.migration_id = '20260131_04_receipt_migration'
      self.description = 'Migrate Metadata records to Receipt format with owner linkage'
      self.dependencies = ['20260131_02_organization_generator']

      def prepare
        # We're migrating FROM metadata keys, but using Receipt model
        @model_class = Onetime::Receipt
        @batch_size = 100
        @migrated_at = Time.now.to_f.to_s

        # Custom scan pattern: look for old metadata keys
        # This overrides the default which would be "receipt:*:object"
        @scan_pattern = 'metadata:*:object'

        # Build lookup mappings
        info "Building email to customer objid mapping..."
        @email_to_customer = Helper.build_email_to_customer_objid_mapping
        info "Found #{@email_to_customer.size} email->customer mappings"

        info "Building email to org mapping..."
        @email_to_org = Helper.build_email_to_org_objid_mapping
        info "Found #{@email_to_org.size} email->org mappings"

        # Also count existing receipts
        info "Existing receipts (new format): #{Onetime::Receipt.instances.size}"
      end

      def migration_needed?
        # Check for old metadata keys
        cursor = '0'
        count = 0
        cursor, keys = dbclient.scan(cursor, match: @scan_pattern, count: 100)
        count = keys.size

        info "Found #{count} metadata keys (sample scan)"
        count > 0
      end

      # Override to load from metadata keys
      def load_from_key(key)
        # Load raw hash data from old metadata key
        data = dbclient.hgetall(key)
        return nil if data.empty?

        # Create a Receipt object but don't save yet
        # We'll populate it with transformed data
        receipt = Onetime::Receipt.new
        data.each do |field, value|
          receipt.send("#{field}=", value) if receipt.respond_to?("#{field}=")
        end

        # Store the original key for reference
        receipt.instance_variable_set(:@_original_key, key)
        receipt
      end

      def process_record(obj, key)
        return unless obj

        # Extract original metadata key
        original_key = obj.instance_variable_get(:@_original_key) || key

        # Skip if this looks like already a receipt key (new format)
        if original_key.start_with?('receipt:')
          track_stat(:skipped_already_receipt)
          return
        end

        # Check if already migrated (has v1_key set)
        if obj.v1_key.to_s.present?
          track_stat(:skipped_already_migrated)
          return
        end

        for_realsies_this_time? do
          migrate_metadata_to_receipt(obj, original_key)
        end

        track_stat(:records_updated)
      end

      private

      def migrate_metadata_to_receipt(obj, original_key)
        # Extract metadata ID from key: metadata:{id}:object
        old_id = original_key.split(':')[1]

        # Get original custid for owner lookup
        # In v1, receipts had custid field (email or 'anon')
        v1_custid = obj.respond_to?(:custid) ? obj.custid.to_s : ''
        v1_custid = 'anon' if v1_custid.empty?

        # Determine new owner_id
        owner_id = if v1_custid == 'anon'
                     'anon'
                   else
                     @email_to_customer[v1_custid] || 'anon'
                   end

        # Determine org_id if authenticated
        org_id = nil
        if owner_id != 'anon'
          org_id = @email_to_org[v1_custid]
        end

        # Generate new objid for receipt if needed
        created = obj.created.to_f
        new_objid = obj.objid.to_s
        if new_objid.empty? || new_objid == old_id
          # Use verifiable identifier pattern for receipts
          new_objid = Familia::VerifiableIdentifier.generate_verifiable_id
        end

        # Build new receipt key
        new_key = "receipt:#{new_objid}:object"

        # Prepare transformed fields
        transformed = build_transformed_fields(obj, {
          objid: new_objid,
          owner_id: owner_id,
          org_id: org_id,
          v1_key: original_key,
          v1_custid: v1_custid,
        })

        # Store original record data
        original_data = dbclient.hgetall(original_key)

        # Write new receipt record
        dbclient.hmset(new_key, *transformed.flatten)

        # Store original for rollback
        original_record = {
          'object' => original_data,
          'key' => original_key,
          'db' => 7,
          'exported_at' => Time.now.utc.iso8601,
        }
        dbclient.set("#{new_key}:_original_record", original_record.to_json)
        dbclient.expire("#{new_key}:_original_record", 86400 * 30)

        # Add to Receipt instances index
        Onetime::Receipt.instances.add(new_objid)

        # Add to organization receipts via participation if authenticated
        if org_id
          add_org_participation(new_objid, org_id, created)
        end

        # Expire old key after grace period
        dbclient.expire(original_key, 86400 * 7) # 7 days

        track_stat(:metadata_converted)
        info "Migrated metadata:#{old_id} -> receipt:#{new_objid[0..7]}..."
      end

      def build_transformed_fields(obj, overrides)
        fields = {}

        # Copy existing fields
        %w[state secret_identifier secret_shortid secret_ttl lifespan
           share_domain passphrase recipients memo created updated].each do |field|
          val = obj.send(field) rescue nil
          fields[field] = val.to_s if val
        end

        # Apply overrides
        overrides.each { |k, v| fields[k.to_s] = v.to_s if v }

        # Field renames: viewed -> previewed, received -> revealed
        if obj.respond_to?(:viewed) && obj.viewed.to_s.present?
          fields['previewed'] = obj.viewed.to_s
        end

        if obj.respond_to?(:received) && obj.received.to_s.present?
          fields['revealed'] = obj.received.to_s
        end

        # Migration tracking
        fields['v1_identifier'] = overrides[:v1_custid].to_s
        fields['migration_status'] = 'completed'
        fields['migrated_at'] = @migrated_at

        fields
      end

      def add_org_participation(receipt_objid, org_objid, score)
        org = Onetime::Organization.load(org_objid) rescue nil
        return unless org

        # Add to organization's receipts sorted set
        # The participates_in relationship auto-generates org.receipts
        org.receipts.add(receipt_objid, score.to_f)
        track_stat(:org_participation_added)
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(OTS::Migration::ReceiptMigration.cli_run)
end
