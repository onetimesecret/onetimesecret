# lib/onetime/cli/migrations/dedupe_relationships_command.rb
#
# frozen_string_literal: true

# Remove JSON-quoted duplicate members from per-instance relationship
# sorted sets created by Familia's `participates_in` declarations.
#
# These are the "target side" sorted sets, e.g.:
#   organization:<id>:members
#   organization:<id>:domains
#   organization:<id>:receipts
#   custom_domain:<id>:receipts
#
# Uses Redis SCAN to discover keys matching each pattern, then dedupes
# each sorted set found.
#
# Usage:
#   bin/ots migrations dedupe-relationships           # Dry run (default)
#   bin/ots migrations dedupe-relationships --run     # Execute removal
#   bin/ots migrations dedupe-relationships --verbose # Show each duplicate
#
# @see https://github.com/onetimesecret/onetimesecret/issues/XXXX

module Onetime
  module CLI
    class DedupeRelationshipsCommand < Command
      desc 'Remove JSON-quoted duplicates from per-instance relationship sorted sets'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute removal (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show each duplicate found'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      # Key patterns for relationship sorted sets (target side of participates_in)
      RELATIONSHIP_PATTERNS = [
        'organization:*:members',
        'organization:*:domains',
        'organization:*:receipts',
        'custom_domain:*:receipts',
      ].freeze

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nDeduplicate Relationship Sorted Sets"
        puts '=' * 60

        dry_run = !run
        print_mode_banner(dry_run)

        stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }

        RELATIONSHIP_PATTERNS.each do |pattern|
          scan_and_dedupe_pattern(pattern, stats, dry_run, verbose)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:duplicates_removed])
      end

      private

      def scan_and_dedupe_pattern(pattern, stats, dry_run, verbose)
        redis         = Familia.dbclient
        keys_found    = 0
        pattern_dupes = 0

        puts "\n  Pattern: #{pattern}"

        redis.scan_each(match: pattern) do |key|
          keys_found           += 1
          stats[:keys_scanned] += 1

          duplicates     = dedupe_sorted_set_key(key, redis, stats, dry_run, verbose)
          pattern_dupes += duplicates
        end

        puts "    #{keys_found} keys scanned, #{pattern_dupes} total duplicates"
      end

      def dedupe_sorted_set_key(key, redis, stats, dry_run, verbose)
        raw_members = redis.zrange(key, 0, -1)
        duplicates  = find_json_quoted_duplicates(raw_members)

        return 0 if duplicates.empty?

        stats[:keys_with_duplicates] += 1
        stats[:duplicates_removed]   += duplicates.size

        if verbose
          puts "    #{key}: #{duplicates.size} duplicates"
          duplicates.each { |d| puts "      - #{d}" }
        end

        unless dry_run
          redis.zrem(key, duplicates)
        end

        duplicates.size
      rescue StandardError => ex
        stats[:errors] << "#{key}: #{ex.message}"
        puts "    Error scanning #{key}: #{ex.message}"
        OT.le "[DedupeRelationships] Error for #{key}: #{ex.message}"
        0
      end

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

      def print_next_steps(dry_run, dup_count)
        return unless dry_run && dup_count > 0

        puts <<~MESSAGE

          To execute removal, run:
            bin/ots migrations dedupe-relationships --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Deduplicate Relationship Sorted Sets

          Usage:
            bin/ots migrations dedupe-relationships [options]

          Description:
            Removes JSON-quoted duplicate members from per-instance
            relationship sorted sets created by participates_in.

            Uses Redis SCAN to discover keys matching each pattern,
            then removes quoted members where the raw form also exists.

          Key patterns scanned:
            organization:*:members
            organization:*:domains
            organization:*:receipts
            custom_domain:*:receipts

          Options:
            --run                 Execute removal (default is dry-run)
            --verbose, -v         Show each duplicate found
            --help, -h            Show this help message

          Examples:
            # Preview (dry run)
            bin/ots migrations dedupe-relationships

            # Execute removal
            bin/ots migrations dedupe-relationships --run

            # Execute with verbose output
            bin/ots migrations dedupe-relationships --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Only removes a quoted member when its raw counterpart exists
            - No data loss: the raw identifier remains intact

        USAGE
        true
      end
    end

    register 'migrations dedupe-relationships', DedupeRelationshipsCommand
  end
end
