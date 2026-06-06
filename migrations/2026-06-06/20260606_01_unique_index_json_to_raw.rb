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
# This migration discovers all unique_index hashes via Familia's introspection
# API (v2.10.1), detects JSON-encoded values, and rewrites them as raw strings.
# Idempotent: already-raw values are skipped.
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

      def prepare
        @descriptors = Familia.stale_indexes
      end

      def migration_needed?
        @descriptors.any?
      end

      def migrate
        run_mode_banner

        @descriptors.each do |descriptor|
          convert_index(descriptor)
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

      def convert_index(descriptor)
        hashkey   = descriptor.owner.public_send(descriptor.index_name)
        index_key = hashkey.dbkey
        converted = 0
        skipped   = 0

        redis.hscan_each(index_key, count: 100) do |field, value|
          unless Familia.legacy_json_encoded?(value)
            skipped += 1
            next
          end

          raw_value = JSON.parse(value)

          if dry_run?
            info "[DRY RUN] #{descriptor.coordinate} field=#{field}: #{value.inspect} -> #{raw_value.inspect}"
          else
            redis.hset(index_key, field, raw_value)
          end

          converted += 1
          track_stat(:entries_converted)
        end

        skipped.times { track_stat(:entries_already_raw) }
        track_stat(:indexes_scanned)

        unless converted.zero?
          label = dry_run? ? 'would convert' : 'converted'
          info "#{descriptor.coordinate}: #{label} #{converted}, already raw #{skipped}"
        end
      end
    end
  end
end

if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::UniqueIndexJsonToRaw.cli_run)
end
