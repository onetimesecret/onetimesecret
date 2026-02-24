# lib/onetime/cli/migrations/dedupe_participations_command.rb
#
# frozen_string_literal: true

# Remove JSON-quoted duplicate members from per-instance participation
# sets (SADD targets from Familia's `participates_in` declarations).
#
# These are the "source side" sets, e.g.:
#   customer:<id>:participations
#   receipt:<id>:participations
#
# These are Redis sets (not sorted sets), so uses SMEMBERS/SREM.
#
# Usage:
#   bin/ots migrations dedupe-participations           # Dry run (default)
#   bin/ots migrations dedupe-participations --run     # Execute removal
#   bin/ots migrations dedupe-participations --verbose # Show each duplicate
#
# @see https://github.com/onetimesecret/onetimesecret/issues/XXXX

require_relative 'deduplication_helper'

module Onetime
  module CLI
    class DedupeParticipationsCommand < Command
      include DeduplicationHelper

      desc 'Remove JSON-quoted duplicates from per-instance participation sets'

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

      # Key patterns for participation sets (source side of participates_in)
      PARTICIPATION_PATTERNS = [
        'customer:*:participations',
        'receipt:*:participations',
      ].freeze

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nDeduplicate Participation Sets"
        puts '=' * 60

        dry_run = !run
        print_mode_banner(dry_run)

        stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }

        PARTICIPATION_PATTERNS.each do |pattern|
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

        redis.scan_each(match: pattern, count: 100) do |key|
          keys_found           += 1
          stats[:keys_scanned] += 1

          duplicates     = dedupe_set_key(key, redis, stats, dry_run, verbose)
          pattern_dupes += duplicates
        end

        puts "    #{keys_found} keys scanned, #{pattern_dupes} total duplicates"
      rescue Redis::BaseError => ex
        OT.le "[DedupeParticipations] Redis error scanning pattern #{pattern}: #{ex.message}"
        raise
      end

      def dedupe_set_key(key, redis, stats, dry_run, verbose)
        raw_members = redis.smembers(key)
        return 0 if raw_members.empty?

        duplicates = find_json_quoted_duplicates(raw_members)

        return 0 if duplicates.empty?

        stats[:keys_with_duplicates] += 1
        stats[:duplicates_removed]   += duplicates.size

        if verbose
          puts "    #{key}: #{duplicates.size} duplicates"
          duplicates.each { |d| puts "      - #{d}" }
        end

        unless dry_run
          redis.srem(key, duplicates)
        end

        duplicates.size
      rescue StandardError => ex
        stats[:errors] << "#{key}: #{ex.message}"
        puts "    Error scanning #{key}: #{ex.message}"
        OT.le "[DedupeParticipations] Error for #{key}: #{ex.message}"
        0
      end

      def print_next_steps(dry_run, dup_count)
        return unless dry_run && dup_count > 0

        puts <<~MESSAGE

          To execute removal, run:
            bin/ots migrations dedupe-participations --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Deduplicate Participation Sets

          Usage:
            bin/ots migrations dedupe-participations [options]

          Description:
            Removes JSON-quoted duplicate members from per-instance
            participation sets (source side of participates_in).

            These are Redis sets (not sorted sets). Uses SMEMBERS/SREM.

          Key patterns scanned:
            customer:*:participations
            receipt:*:participations

          Options:
            --run                 Execute removal (default is dry-run)
            --verbose, -v         Show each duplicate found
            --help, -h            Show this help message

          Examples:
            # Preview (dry run)
            bin/ots migrations dedupe-participations

            # Execute removal
            bin/ots migrations dedupe-participations --run

            # Execute with verbose output
            bin/ots migrations dedupe-participations --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Only removes a quoted member when its raw counterpart exists
            - No data loss: the raw identifier remains intact

        USAGE
        true
      end
    end

    register 'migrations dedupe-participations', DedupeParticipationsCommand
  end
end
