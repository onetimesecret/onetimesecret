# lib/onetime/cli/migrations/deduplication_helper.rb
#
# frozen_string_literal: true

# Shared logic for deduplicate/normalize commands that clean up
# JSON-quoted members in Redis sorted sets and sets.
#
# Familia v2's serialize_value JSON-encodes plain strings, so
# identifiers written by application code become "\"abc\"" while
# migration scripts wrote them raw as "abc". Redis sorted sets
# deduplicate by exact byte value, so both forms can coexist.
#
# Two cases arise:
#   1. Both "\"abc\"" and "abc" exist → remove the quoted duplicate
#   2. Only "\"abc\"" exists (raw was never written) → normalize
#      by replacing it with "abc"
#
# This module provides detection logic for both cases and common
# output helpers.

module Onetime
  module CLI
    module DeduplicationHelper
      # A member is a JSON-quoted duplicate if it starts and ends with
      # a literal double-quote character AND the unquoted form also
      # exists in the same collection. These are safe to simply remove.
      def find_json_quoted_duplicates(members)
        raw_lookup = members.to_set
        members.select do |m|
          m.start_with?('"') && m.end_with?('"') && m.length > 2 &&
            raw_lookup.include?(m[1..-2])
        end
      end

      # Find ALL members that are JSON-quoted (wrapped in literal
      # double-quote characters), regardless of whether the unquoted
      # form exists. This is a superset of find_json_quoted_duplicates.
      # Members found here but NOT in find_json_quoted_duplicates are
      # "orphaned" quoted entries that need normalization (replace with
      # the unquoted form) rather than simple removal.
      def find_json_quoted_members(members)
        members.select do |m|
          m.start_with?('"') && m.end_with?('"') && m.length > 2
        end
      end

      # Find quoted members whose unquoted form does NOT already exist
      # in the collection. These need normalization: remove the quoted
      # form and add the unquoted form.
      def find_normalize_only_members(members)
        raw_lookup = members.to_set
        find_json_quoted_members(members).reject do |m|
          raw_lookup.include?(m[1..-2])
        end
      end

      def print_mode_banner(dry_run)
        return unless dry_run

        puts "\nDRY RUN MODE - No changes will be made"
        puts "To execute changes, run with --run flag\n"
      end

      def print_results(stats, dry_run)
        puts "\n" + ('=' * 60)
        action = dry_run ? 'Preview' : 'Complete'
        puts "Deduplication & Normalization #{action}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Keys scanned:          #{stats[:keys_scanned]}"
        puts "  Keys with duplicates:  #{stats[:keys_with_duplicates]}"
        puts "  Duplicates #{dry_run ? 'found' : 'removed'}:     #{stats[:duplicates_removed]}"

        if stats.key?(:members_normalized)
          puts "  Members #{dry_run ? 'to normalize' : 'normalized'}:  #{stats[:members_normalized]}"
        end

        return unless stats[:errors].any?

        puts "\n  Errors: #{stats[:errors].size}"
        stats[:errors].each { |err| puts "    - #{err}" }
      end
    end
  end
end
