#!/usr/bin/env ruby
# migrations/2026-01-31/04a_receipt_repair.rb
#
# frozen_string_literal: true

# Receipt Repair: Fix secret_identifier/secret_shortid from v1 backup
#
# The original receipt migration (04_receipt_migration.rb) had a bug where
# secret_key (v1 field) was not mapped to secret_identifier (v2 field).
# This repair script reads the _original_record backup and populates the
# missing fields.
#
# Usage:
#   bundle exec ruby migrations/2026-01-31/04a_receipt_repair.rb           # Dry run
#   bundle exec ruby migrations/2026-01-31/04a_receipt_repair.rb --run     # Actual run

require 'bundler/setup'
require 'familia/migration'

# Only boot if running directly (not via bin/ots migrate)
unless defined?(Onetime::CLI)
  require_relative '../../lib/onetime'
  OT.boot! :app
end

module OTS
  module Migration
    class ReceiptRepair < Familia::Migration::Model
      self.migration_id = '20260131_04a_receipt_repair'
      self.description = 'Repair secret_identifier/secret_shortid on migrated receipts'
      self.dependencies = ['20260131_04_receipt_migration']

      def prepare
        @model_class = Onetime::Receipt
        @batch_size = 100
        @repaired = 0
        @already_ok = 0
        @no_backup = 0
        @no_secret_key = 0

        info "Scanning receipts for missing secret_identifier..."
      end

      def migration_needed?
        # Check if any receipts have empty secret_identifier but have v1_key
        count = 0
        @model_class.instances.revrangeraw(0, 100).each do |identifier|
          receipt = @model_class.load(identifier) rescue nil
          next unless receipt
          next unless receipt.v1_key.to_s.present? # Only migrated receipts
          next if receipt.secret_identifier.to_s.present? # Already has value

          count += 1
        end

        info "Found #{count} receipts needing repair (sample of first 100)"
        count > 0
      end

      def process_record(obj, key)
        return unless obj

        # Skip if not a migrated receipt (no v1_key)
        unless obj.v1_key.to_s.present?
          track_stat(:skipped_not_migrated)
          return
        end

        # Skip if already has secret_identifier
        if obj.secret_identifier.to_s.present?
          @already_ok += 1
          track_stat(:skipped_already_ok)
          return
        end

        # First, try to read secret_key from current receipt (deprecated field may still exist)
        secret_key = obj.secret_key.to_s if obj.respond_to?(:secret_key)

        # If not found, try the original record backup
        if secret_key.to_s.empty?
          backup_key = "#{key}:_original_record"
          backup_json = dbclient.get(backup_key)

          if backup_json
            backup = JSON.parse(backup_json) rescue nil
            original_data = backup&.dig('object') || {}
            secret_key = original_data['secret_key'].to_s
          else
            @no_backup += 1
            track_stat(:no_backup_found)
            debug "No backup found for #{key}"
          end
        end

        unless secret_key.present?
          @no_secret_key += 1
          track_stat(:no_secret_key_in_backup)
          # This is expected for receipts where secret was already revealed/burned
          debug "No secret_key found for #{key} (state: #{obj.state})"
          return
        end

        for_realsies_this_time? do
          repair_receipt(obj, key, secret_key)
        end

        track_stat(:records_updated)
      end

      def post_process
        info "Repair Summary:"
        info "  Repaired: #{@repaired}"
        info "  Already OK: #{@already_ok}"
        info "  No backup found: #{@no_backup}"
        info "  No secret_key (revealed/burned): #{@no_secret_key}"
      end

      private

      def repair_receipt(receipt, key, secret_key)
        # Update the receipt fields
        dbclient.hset(key, 'secret_identifier', secret_key)
        dbclient.hset(key, 'secret_shortid', secret_key.slice(0, 8))

        @repaired += 1
        info "Repaired #{receipt.shortid}: secret_identifier=#{secret_key.slice(0, 8)}..."
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(OTS::Migration::ReceiptRepair.cli_run)
end
