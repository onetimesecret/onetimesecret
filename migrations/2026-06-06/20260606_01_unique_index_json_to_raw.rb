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
# This migration scans every known unique_index hash, detects JSON-encoded
# values, and rewrites them as raw strings. Idempotent: already-raw values
# are skipped.
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

      GLOBAL_INDEX_KEYS = [
        'custom_domain:display_domain_index',
        'customer:email_index',
        'organization:contact_email_index',
        'org_membership:token_lookup',
        'organization:stripe_customer_id_index',
        'organization:stripe_subscription_id_index',
        'organization:stripe_checkout_email_index',
        'organization:billing_email_index',
      ].freeze

      SCOPED_INDEX_PATTERNS = [
        'organization:*:email_index',
      ].freeze

      def prepare
        @index_keys = discover_index_keys
      end

      def migration_needed?
        @index_keys.any? { |key| has_json_encoded_values?(key) }
      end

      def migrate
        run_mode_banner

        @index_keys.each do |key|
          convert_index(key)
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

      def discover_index_keys
        keys = []

        GLOBAL_INDEX_KEYS.each do |key|
          keys << key if redis.exists?(key)
        end

        SCOPED_INDEX_PATTERNS.each do |pattern|
          redis.scan_each(match: pattern) do |key|
            keys << key
          end
        end

        keys
      end

      def has_json_encoded_values?(index_key)
        redis.hscan_each(index_key, count: 100) do |_field, value|
          return true if json_encoded_string?(value)
        end
        false
      end

      def convert_index(index_key)
        converted = 0
        skipped   = 0

        redis.hscan_each(index_key, count: 100) do |field, value|
          unless json_encoded_string?(value)
            skipped += 1
            next
          end

          raw_value = JSON.parse(value)

          if dry_run?
            info "[DRY RUN] #{index_key} field=#{field}: #{value.inspect} -> #{raw_value.inspect}"
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
          info "#{index_key}: #{label} #{converted}, already raw #{skipped}"
        end
      end

      # A value is JSON-encoded if it's a string that starts and ends with
      # a double-quote character — e.g. "\"dom_abc123\"". A raw identifier
      # like "dom_abc123" does not start with a quote.
      def json_encoded_string?(value)
        return false unless value.is_a?(String)
        return false if value.empty?
        return false unless value.start_with?('"') && value.end_with?('"')

        JSON.parse(value).is_a?(String)
      rescue JSON::ParserError
        false
      end
    end
  end
end

if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::UniqueIndexJsonToRaw.cli_run)
end
