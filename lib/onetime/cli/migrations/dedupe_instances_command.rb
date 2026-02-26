# lib/onetime/cli/migrations/dedupe_instances_command.rb
#
# frozen_string_literal: true

# Remove JSON-quoted duplicate members from class-level sorted sets
# and sets (`:instances`, `:expiration_timeline`, `:warnings_sent`).
#
# Familia v2's serialize_value JSON-encodes plain strings, so identifiers
# written by application code become "\"abc\"" while migration scripts
# wrote them raw as "abc". Redis sorted sets deduplicate by exact byte
# value, so both forms coexist. This command removes the JSON-quoted
# form when the raw counterpart is present.
#
# Usage:
#   bin/ots migrations dedupe-instances           # Dry run (default)
#   bin/ots migrations dedupe-instances --run     # Execute removal
#   bin/ots migrations dedupe-instances --verbose # Show each duplicate
#
# @see https://github.com/onetimesecret/onetimesecret/issues/XXXX

require_relative 'deduplication_helper'

module Onetime
  module CLI
    class DedupeInstancesCommand < Command
      include DeduplicationHelper

      desc 'Remove JSON-quoted duplicates from class-level instance collections'

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

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nDeduplicate Class-Level Instance Collections"
        puts '=' * 60

        dry_run = !run
        print_mode_banner(dry_run)

        stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }

        sorted_set_collections.each do |label, redis_key|
          dedupe_sorted_set(label, redis_key, stats, dry_run, verbose)
        end

        set_collections.each do |label, redis_key|
          dedupe_set(label, redis_key, stats, dry_run, verbose)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:duplicates_removed])
      end

      private

      # Class-level sorted sets: instances for each model
      def sorted_set_collections
        [
          ['Customer.instances',              Onetime::Customer.instances.dbkey],
          ['Organization.instances',          Onetime::Organization.instances.dbkey],
          ['CustomDomain.instances',          Onetime::CustomDomain.instances.dbkey],
          ['Receipt.instances',               Onetime::Receipt.instances.dbkey],
          ['Secret.instances',                Onetime::Secret.instances.dbkey],
          ['Feedback.instances',              Onetime::Feedback.instances.dbkey],
          ['OrganizationMembership.instances', Onetime::OrganizationMembership.instances.dbkey],
          ['Receipt.expiration_timeline', Onetime::Receipt.expiration_timeline.dbkey],
        ]
      end

      # Class-level sets (SADD-based)
      def set_collections
        [
          ['Receipt.warnings_sent', Onetime::Receipt.warnings_sent.dbkey],
        ]
      end

      def dedupe_sorted_set(label, redis_key, stats, dry_run, verbose)
        stats[:keys_scanned] += 1
        redis                 = Familia.dbclient

        raw_members = redis.zrange(redis_key, 0, -1)
        if raw_members.empty?
          puts "  Scanning #{label}... empty collection"
          return
        end

        duplicates = find_json_quoted_duplicates(raw_members)

        if duplicates.empty?
          puts "  Scanning #{label}... 0 duplicates"
          return
        end

        stats[:keys_with_duplicates] += 1
        stats[:duplicates_removed]   += duplicates.size

        puts "  Scanning #{label}... #{duplicates.size} duplicates found"

        if verbose
          duplicates.each { |d| puts "    - #{d}" }
        end

        unless dry_run
          redis.zrem(redis_key, duplicates)
        end
      rescue StandardError => ex
        stats[:errors] << "#{label}: #{ex.message}"
        puts "  Error scanning #{label}: #{ex.message}"
        OT.le "[DedupeInstances] Error for #{redis_key}: #{ex.message}"
      end

      def dedupe_set(label, redis_key, stats, dry_run, verbose)
        stats[:keys_scanned] += 1
        redis                 = Familia.dbclient

        raw_members = redis.smembers(redis_key)
        if raw_members.empty?
          puts "  Scanning #{label}... empty collection"
          return
        end

        duplicates = find_json_quoted_duplicates(raw_members)

        if duplicates.empty?
          puts "  Scanning #{label}... 0 duplicates"
          return
        end

        stats[:keys_with_duplicates] += 1
        stats[:duplicates_removed]   += duplicates.size

        puts "  Scanning #{label}... #{duplicates.size} duplicates found"

        if verbose
          duplicates.each { |d| puts "    - #{d}" }
        end

        unless dry_run
          redis.srem(redis_key, duplicates)
        end
      rescue StandardError => ex
        stats[:errors] << "#{label}: #{ex.message}"
        puts "  Error scanning #{label}: #{ex.message}"
        OT.le "[DedupeInstances] Error for #{redis_key}: #{ex.message}"
      end

      def print_next_steps(dry_run, dup_count)
        return unless dry_run && dup_count > 0

        puts <<~MESSAGE

          To execute removal, run:
            bin/ots migrations dedupe-instances --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Deduplicate Class-Level Instance Collections

          Usage:
            bin/ots migrations dedupe-instances [options]

          Description:
            Removes JSON-quoted duplicate members from class-level sorted
            sets and sets (:instances, :expiration_timeline, :warnings_sent).

            Familia v2's serialize_value JSON-encodes identifiers, creating
            duplicates when both raw and quoted forms exist. This command
            removes the quoted form when the raw counterpart is present.

          Models scanned:
            Customer, Organization, CustomDomain, Receipt, Secret,
            Feedback, OrganizationMembership (instances sorted sets)
            Receipt (expiration_timeline sorted set, warnings_sent set)

          Options:
            --run                 Execute removal (default is dry-run)
            --verbose, -v         Show each duplicate found
            --help, -h            Show this help message

          Examples:
            # Preview (dry run)
            bin/ots migrations dedupe-instances

            # Execute removal
            bin/ots migrations dedupe-instances --run

            # Execute with verbose output
            bin/ots migrations dedupe-instances --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Only removes a quoted member when its raw counterpart exists
            - No data loss: the raw identifier remains intact

        USAGE
        true
      end
    end

    register 'migrations dedupe-instances', DedupeInstancesCommand
  end
end
