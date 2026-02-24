# lib/onetime/cli/migrations/deduplication_helper.rb
#
# frozen_string_literal: true

# Shared logic for deduplicate commands that remove JSON-quoted
# duplicate members from Redis sorted sets and sets.
#
# Familia v2's serialize_value JSON-encodes plain strings, so
# identifiers written by application code become "\"abc\"" while
# migration scripts wrote them raw as "abc". This module provides
# the detection logic and common output helpers.

module Onetime
  module CLI
    module DeduplicationHelper
      # A member is a JSON-quoted duplicate if it starts and ends with
      # a literal double-quote character AND the unquoted form also
      # exists in the same collection.
      def find_json_quoted_duplicates(members)
        raw_lookup = members.to_set
        members.select do |m|
          m.start_with?('"') && m.end_with?('"') && m.length > 2 &&
            raw_lookup.include?(m[1..-2])
        end
      end

      def print_mode_banner(dry_run)
        return unless dry_run

        puts "\nDRY RUN MODE - No changes will be made"
        puts "To execute removal, run with --run flag\n"
      end

      def print_results(stats, dry_run)
        puts "\n" + ('=' * 60)
        puts "Deduplication #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Keys scanned:          #{stats[:keys_scanned]}"
        puts "  Keys with duplicates:  #{stats[:keys_with_duplicates]}"
        puts "  Duplicates #{dry_run ? 'found' : 'removed'}:     #{stats[:duplicates_removed]}"

        return unless stats[:errors].any?

        puts "\n  Errors: #{stats[:errors].size}"
        stats[:errors].each { |err| puts "    - #{err}" }
      end
    end
  end
end
