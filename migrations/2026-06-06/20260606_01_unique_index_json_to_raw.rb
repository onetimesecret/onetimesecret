# migrations/2026-06-06/20260606_01_unique_index_json_to_raw.rb
#
# frozen_string_literal: true

#
# Convert unique_index values from legacy JSON-encoded strings to raw strings
#
# Familia 2.9.x stored unique_index values as JSON-encoded strings:
#   HSET custom_domain:display_domain_index example.com "\"dom_abc123\""
#
# Familia 2.10 stores them raw:
#   HSET custom_domain:display_domain_index example.com dom_abc123
#
# Version behaviour this migration straddles:
#   - 2.10.0 read the stored value literally, so a finder returned the quoted
#     id, Model.load matched no record, and nil came back — a SILENT break of
#     CustomDomain.from_display_domain (and, downstream, OrganizationLoader's
#     domain-based selection for custom-domain SSO).
#   - 2.10.1 (the version we run) strips the legacy encoding on read, so the
#     finder self-heals — but it warns on EVERY read, leaves storage stale, and
#     keeps the boot guard flagging the index. The app stays dependent on that
#     read-time shim until the data is rewritten.
#
# This migration rewrites every legacy entry to its raw form so storage is
# consistent: no per-read warnings, no boot-guard noise, no shim dependence.
# It is idempotent — entries already raw are left untouched, so re-runs are
# no-ops.
#
# Discovery uses Familia v2.10.1's introspection (Familia.stale_indexes) for
# class-level unique indexes — no hardcoded key list. Organization-scoped
# indexes are handled via an explicit SCAN pattern because
# IndexDescriptor#stale_format? cannot sample an instance-scoped index without
# a scope argument, so Familia.stale_indexes intentionally omits them.
#
# Usage:
#   bin/ots migrate 20260606_01_unique_index_json_to_raw         # Preview
#   bin/ots migrate --run 20260606_01_unique_index_json_to_raw   # Execute
#
# Refs: #3347, delano/familia#302
require 'familia/migration'

module Onetime
  module Migrations
    # Convert legacy JSON-encoded unique_index values to the raw 2.10 format.
    class UniqueIndexJsonToRaw < Familia::Migration::Base
      self.migration_id = '20260606_01_unique_index_json_to_raw'
      self.description  = 'Convert unique_index values from JSON-encoded strings to raw (Familia 2.10)'
      self.dependencies = []

      # Organization-scoped unique index key patterns.
      #
      # Familia.stale_indexes only covers class-level indexes:
      # IndexDescriptor#stale_format? can't sample an instance-scoped index
      # without a scope argument, so the aggregator omits them. These patterns
      # are therefore listed explicitly. Hardcoding is acceptable here because
      # the migration runs once against a known data snapshot.
      #
      # Source declaration (lib/onetime/models/customer.rb):
      #   unique_index :email, :email_index, within: Onetime::Organization
      SCOPED_INDEX_PATTERNS = [
        'organization:*:email_index',
      ].freeze

      # SCAN/HSCAN batch size — large enough to keep round-trips low without
      # blocking the server on any single call.
      SCAN_BATCH = 1000

      def prepare
        unless Familia.respond_to?(:stale_indexes)
          loaded = defined?(Familia::VERSION) ? Familia::VERSION : 'unknown'
          raise Familia::Migration::Errors::PreconditionFailed,
            'Familia >= 2.10.1 required for unique-index introspection ' \
            "(Familia.stale_indexes). Loaded: #{loaded}. " \
            'Bump the gem with `bundle lock --update familia` and `bundle install`.'
        end

        # Class-level unique indexes whose sampled values are still in the
        # legacy JSON-encoded format. Returns IndexDescriptor objects.
        @descriptors = Familia.stale_indexes

        # Org-scoped index keys (introspection can't reach these).
        @scoped_keys = discover_scoped_index_keys
      end

      def migration_needed?
        @descriptors.any? || @scoped_keys.any? { |key| legacy_values?(key, scoped_client) }
      end

      def migrate
        run_mode_banner

        @descriptors.each do |descriptor|
          hashkey = descriptor.owner.public_send(descriptor.index_name)
          convert_index(hashkey.dbkey, hashkey.dbclient, label: descriptor.coordinate)
        end

        @scoped_keys.each { |key| convert_index(key, scoped_client, label: key) }

        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          converted = @stats[:entries_converted]
          if converted.zero?
            info 'No legacy JSON-encoded values found — indexes already consistent.'
          elsif mode == :dry_run
            info "Re-run with --run to convert #{converted} value(s)."
          else
            info "Converted #{converted} value(s) to raw strings."
          end
        end

        true
      end

      private

      # The org-scoped index keys live in the scope class' database
      # (Onetime::Organization), so SCAN/probe against its client.
      def scoped_client
        @scoped_client ||= Onetime::Organization.dbclient
      end

      def discover_scoped_index_keys
        keys = []
        SCOPED_INDEX_PATTERNS.each do |pattern|
          scoped_client.scan_each(match: pattern, count: SCAN_BATCH) { |key| keys << key }
        end
        keys.uniq
      end

      # Rewrite every legacy JSON-encoded value in the index hash to its raw
      # form. Writes happen inline; HSET on an existing field during HSCAN is
      # safe (it neither adds nor removes fields, so the cursor is unaffected).
      def convert_index(key, client, label:)
        track_stat(:keys_scanned)

        client.hscan_each(key, count: SCAN_BATCH) do |field, value|
          unless Familia.legacy_json_encoded?(value)
            track_stat(:entries_already_raw)
            next
          end

          raw = strip_legacy(value)
          if dry_run?
            info "[DRY RUN] #{label} #{field}: #{value.inspect} -> #{raw.inspect}"
          else
            client.hset(key, field, raw)
          end
          track_stat(:entries_converted)
        end
      end

      # Probe a hash for any legacy-encoded value (short-circuits on first hit).
      def legacy_values?(key, client)
        client.hscan_each(key, count: SCAN_BATCH).any? do |_field, value|
          Familia.legacy_json_encoded?(value)
        end
      end

      # Strip the surrounding JSON quotes, mirroring Familia's read path
      # (DataType::Serialization#strip_legacy_json_encoding) so the rewritten
      # value is byte-identical to what the 2.10 reader produces — which is what
      # makes the index read as "current" afterward. Index identifiers (UUIDs /
      # prefixed IDs) never contain escaped characters, so a plain slice is
      # exact; it also can't raise the way JSON.parse would on unexpected data.
      #
      # Guards on legacy_json_encoded? like the upstream method does, so it
      # returns non-legacy values untouched and never slices a too-short string
      # into nil (legacy_json_encoded? already requires length > 2 — this just
      # makes the invariant self-documenting and the method safe in isolation).
      def strip_legacy(value)
        return value unless Familia.legacy_json_encoded?(value)

        value[1..-2]
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::UniqueIndexJsonToRaw.cli_run)
end
