# migrations/2026-06-06/20260606_01_unique_index_json_to_raw.rb
#
# frozen_string_literal: true

#
# Strip JSON encoding from unique_index hash values after Familia 2.10 upgrade
#
# Familia 2.9.x stored unique_index values as JSON-encoded strings:
#   HSET custom_domain:display_domain_index example.com "\"dom_abc123\""
#
# Familia 2.10 stores them as raw strings:
#   HSET custom_domain:display_domain_index example.com dom_abc123
#
# After upgrading, lookups return the quoted identifier (e.g. "\"dom_abc123\"")
# and Model.load silently returns nil because no record has that literal ID.
# This breaks CustomDomain.from_display_domain and any other unique_index
# finder until the index is rebuilt.
#
# Uses Familia's introspection API (v2.10.1) to discover stale class-level
# indexes, then falls back to SCAN for org-scoped indexes that the
# introspection API intentionally excludes (it can't sample instance-scoped
# indexes without a scope argument). Idempotent: already-raw values are
# skipped.
#
# Usage:
#   bin/ots migrate 20260606_01_unique_index_json_to_raw           # Preview
#   bin/ots migrate --run 20260606_01_unique_index_json_to_raw     # Execute
#
# Refs: #3347
require 'familia/migration'
require 'json'

module Onetime
  module Migrations
    class UniqueIndexJsonToRaw < Familia::Migration::Base
      self.migration_id = '20260606_01_unique_index_json_to_raw'
      self.description  = 'Convert unique_index values from JSON-encoded strings to raw strings (Familia 2.10)'
      self.dependencies = []

      # Org-scoped unique_index hashes that Familia.stale_indexes cannot
      # discover (instance-scoped indexes need a scope argument to sample).
      # These are fixed patterns tied to the model declarations at the time
      # this migration was written — acceptable because the migration runs
      # once against a known data snapshot.
      SCOPED_INDEX_PATTERNS = [
        'organization:*:email_index',
      ].freeze

      def prepare
        unless Familia.respond_to?(:stale_indexes)
          raise Familia::Problem,
            'This migration requires Familia >= 2.10.1 (introspection API). ' \
            'Update the familia gem and re-run.'
        end

        @descriptors  = Familia.stale_indexes
        @scoped_keys  = discover_scoped_index_keys
      end

      def migration_needed?
        @descriptors.any? || @scoped_keys.any? { |key| has_legacy_values?(key) }
      end

      def migrate
        run_mode_banner

        @descriptors.each do |descriptor|
          convert_descriptor(descriptor)
        end

        @scoped_keys.each do |key|
          convert_raw_key(key)
        end

        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          converted = @stats[:entries_converted] || 0
          if converted.zero?
            info 'No JSON-encoded values found — indexes are already consistent.'
          elsif mode == :dry_run
            info "Re-run with --run to convert #{converted} value(s)."
          else
            info "Converted #{converted} value(s) to raw strings."
          end
        end

        true
      end

      private

      def discover_scoped_index_keys
        keys = []
        SCOPED_INDEX_PATTERNS.each do |pattern|
          redis.scan_each(match: pattern) { |key| keys << key }
        end
        keys
      end

      def has_legacy_values?(index_key)
        redis.hscan_each(index_key, count: 100) do |_field, value|
          return true if Familia.legacy_json_encoded?(value)
        end
        false
      end

      def convert_descriptor(descriptor)
        hashkey   = descriptor.owner.public_send(descriptor.index_name)
        convert_raw_key(hashkey.dbkey, label: descriptor.coordinate)
      end

      def convert_raw_key(index_key, label: index_key)
        converted = 0
        skipped   = 0

        redis.hscan_each(index_key, count: 100) do |field, value|
          unless Familia.legacy_json_encoded?(value)
            skipped += 1
            next
          end

          raw_value = JSON.parse(value)

          if dry_run?
            info "[DRY RUN] #{label} field=#{field}: #{value.inspect} -> #{raw_value.inspect}"
          else
            redis.hset(index_key, field, raw_value)
          end

          converted += 1
          track_stat(:entries_converted)
        end

        skipped.times { track_stat(:entries_already_raw) }
        track_stat(:indexes_scanned)

        unless converted.zero?
          verb = dry_run? ? 'would convert' : 'converted'
          info "#{label}: #{verb} #{converted}, already raw #{skipped}"
        end
      end
    end
  end
end

if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::UniqueIndexJsonToRaw.cli_run)
end
