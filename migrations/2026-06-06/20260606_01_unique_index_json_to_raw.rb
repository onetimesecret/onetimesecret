# migrations/2026-06-06/20260606_01_unique_index_json_to_raw.rb
#
# frozen_string_literal: true

#
# Rewrite unique_index values from legacy JSON-encoded strings to raw strings
#
# Familia 2.10 stores unique_index values as raw strings (e.g. "dom_abc123")
# instead of the JSON-encoded form (e.g. "\"dom_abc123\"") written by 2.9.x.
# After upgrading, a lookup against an index still holding the legacy form
# returns the quoted string, and Model.load returns nil — silently breaking
# generated finders such as CustomDomain.from_display_domain (and, downstream,
# OrganizationLoader's domain-based selection for every custom-domain SSO
# login) until the indexes are rebuilt.
#
# This migration rewrites every legacy-encoded entry to its raw form so the
# 2.10 read path resolves identifiers correctly. It is idempotent: entries
# already in raw form are left untouched, so re-runs are no-ops.
#
# Discovery uses Familia v2.10.1's introspection (Familia.stale_indexes) for
# class-level unique indexes — no hardcoded key list. Organization-scoped
# indexes are handled via an explicit SCAN pattern list because
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
      self.description  = 'Rewrite unique_index values from legacy JSON-encoded strings to raw (Familia 2.10)'
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
        @stale_descriptors = Familia.stale_indexes
      end

      def migration_needed?
        return true if @stale_descriptors.any?

        # Scoped indexes aren't covered by stale_indexes; probe them directly.
        client = Onetime::Organization.dbclient
        scoped_index_keys.any? { |key| legacy_entries?(key, client) }
      end

      def migrate
        run_mode_banner

        rewrite_class_level_indexes
        rewrite_scoped_indexes

        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          info(mode == :dry_run ? 'Re-run with --run to apply changes.' : 'Index rewrite complete.')
        end

        true
      end

      private

      # --- Class-level indexes (discovered via Familia introspection) ---

      def rewrite_class_level_indexes
        @stale_descriptors.each do |descriptor|
          hashkey = descriptor.owner.public_send(descriptor.index_name)
          info "Class-level index #{descriptor.coordinate} -> #{hashkey.dbkey}"
          rewrite_hash(hashkey.dbkey, hashkey.dbclient)
          track_stat(:class_indexes_processed)
        end
      end

      # --- Organization-scoped indexes (explicit SCAN patterns) ---

      def rewrite_scoped_indexes
        client = Onetime::Organization.dbclient
        scoped_index_keys.each do |key|
          info "Scoped index #{key}"
          rewrite_hash(key, client)
          track_stat(:scoped_keys_processed)
        end
      end

      # Resolve every org-scoped index key once. The scoped keys live in the
      # scope class' database (Onetime::Organization), so SCAN against its
      # client.
      def scoped_index_keys
        @scoped_index_keys ||= begin
          client = Onetime::Organization.dbclient
          SCOPED_INDEX_PATTERNS.flat_map do |pattern|
            client.scan_each(match: pattern, count: SCAN_BATCH).to_a
          end.uniq
        end
      end

      # --- Shared rewrite logic ---

      # Rewrite every legacy JSON-encoded value in the given hash to its raw
      # form. Collects the rewrites during a single HSCAN pass, then applies
      # them afterward — keeping the scan cursor independent of the writes.
      def rewrite_hash(key, client)
        rewrites = {}
        client.hscan_each(key, count: SCAN_BATCH) do |field, value|
          next unless Familia.legacy_json_encoded?(value)

          rewrites[field] = strip_legacy(value)
        end

        return if rewrites.empty?

        if dry_run?
          track_stat(:would_rewrite_entries, rewrites.size)
          rewrites.first(5).each do |field, raw|
            info "  [DRY RUN] would rewrite #{field} -> #{raw.inspect}"
          end
          info "  [DRY RUN] ... and #{rewrites.size - 5} more" if rewrites.size > 5
          return
        end

        rewrites.each { |field, raw| client.hset(key, field, raw) }
        track_stat(:rewritten_entries, rewrites.size)
        info "  rewrote #{rewrites.size} entries"
      end

      # Probe a hash for any legacy-encoded value (short-circuits on first hit).
      def legacy_entries?(key, client)
        client.hscan_each(key, count: SCAN_BATCH).any? do |_field, value|
          Familia.legacy_json_encoded?(value)
        end
      end

      # Strip the surrounding JSON quotes, mirroring Familia's read path
      # (DataType::Serialization#strip_legacy_json_encoding) so the rewritten
      # value is byte-identical to what the 2.10 reader would have produced.
      # Index identifiers (UUIDs / prefixed IDs) never contain escaped
      # characters, so a plain slice is exact and avoids a JSON parse.
      def strip_legacy(value)
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
