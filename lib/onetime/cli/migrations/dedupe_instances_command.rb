# lib/onetime/cli/migrations/dedupe_instances_command.rb
#
# frozen_string_literal: true

# Deduplicate and normalize JSON-quoted members in class-level sorted
# sets and sets (`:instances`, `:expiration_timeline`, `:warnings_sent`).
#
# Familia v2's serialize_value JSON-encodes plain strings, so identifiers
# written by application code become "\"abc\"" while migration scripts
# wrote them raw as "abc". Redis sorted sets deduplicate by exact byte
# value, so both forms can coexist.
#
# This command handles two cases:
#   1. Deduplication: Both quoted and raw forms exist → remove quoted
#   2. Normalization: Only the quoted form exists → replace with raw
#
# Usage:
#   bin/ots migrations dedupe-instances           # Dry run (default)
#   bin/ots migrations dedupe-instances --run     # Execute changes
#   bin/ots migrations dedupe-instances --verbose # Show each entry
#
# @see https://github.com/onetimesecret/onetimesecret/issues/XXXX

require_relative 'deduplication_helper'

module Onetime
  module CLI
    class DedupeInstancesCommand < Command
      include DeduplicationHelper

      desc 'Deduplicate and normalize JSON-quoted members in class-level instance collections'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute changes (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show each duplicate and normalized entry'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nDeduplicate & Normalize Class-Level Instance Collections"
        puts '=' * 60

        dry_run = !run
        print_mode_banner(dry_run)

        stats = {
          keys_scanned: 0,
          keys_with_duplicates: 0,
          duplicates_removed: 0,
          members_normalized: 0,
          errors: [],
        }

        sorted_set_collections.each do |label, redis_key|
          dedupe_sorted_set(label, redis_key, stats, dry_run, verbose)
          normalize_sorted_set(label, redis_key, stats, dry_run, verbose)
        end

        set_collections.each do |label, redis_key|
          dedupe_set(label, redis_key, stats, dry_run, verbose)
          normalize_set(label, redis_key, stats, dry_run, verbose)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:duplicates_removed] + stats[:members_normalized])
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

      # Normalize quoted-only members in a sorted set: remove the
      # quoted form and add the unquoted form with the same score.
      # Only acts on members where the unquoted form does NOT already
      # exist (those cases are handled by dedupe_sorted_set).
      def normalize_sorted_set(label, redis_key, stats, dry_run, verbose)
        redis = Familia.dbclient

        # Re-read members to reflect any deduplication already applied
        raw_members = redis.zrange(redis_key, 0, -1)
        return if raw_members.empty?

        to_normalize = find_normalize_only_members(raw_members)
        return if to_normalize.empty?

        stats[:members_normalized] += to_normalize.size

        puts "  Normalizing #{label}... #{to_normalize.size} quoted-only members"

        if verbose
          to_normalize.each { |m| puts "    ~ #{m} -> #{m[1..-2]}" }
        end

        return if dry_run

        # Phase 1: collect scores in a single pipeline round-trip
        scores = redis.pipelined do |pipe|
          to_normalize.each { |quoted| pipe.zscore(redis_key, quoted) }
        end

        # Phase 2: batch all mutations in a single pipeline round-trip
        redis.pipelined do |pipe|
          to_normalize.each_with_index do |quoted, idx|
            unquoted = quoted[1..-2]
            pipe.zrem(redis_key, quoted)
            pipe.zadd(redis_key, scores[idx], unquoted)
          end
        end
      rescue StandardError => ex
        stats[:errors] << "#{label} (normalize): #{ex.message}"
        puts "  Error normalizing #{label}: #{ex.message}"
        OT.le "[DedupeInstances] Normalize error for #{redis_key}: #{ex.message}"
      end

      # Normalize quoted-only members in a set: remove the quoted
      # form and add the unquoted form. Only acts on members where
      # the unquoted form does NOT already exist.
      def normalize_set(label, redis_key, stats, dry_run, verbose)
        redis = Familia.dbclient

        raw_members = redis.smembers(redis_key)
        return if raw_members.empty?

        to_normalize = find_normalize_only_members(raw_members)
        return if to_normalize.empty?

        stats[:members_normalized] += to_normalize.size

        puts "  Normalizing #{label}... #{to_normalize.size} quoted-only members"

        if verbose
          to_normalize.each { |m| puts "    ~ #{m} -> #{m[1..-2]}" }
        end

        return if dry_run

        redis.pipelined do |pipe|
          to_normalize.each do |quoted|
            unquoted = quoted[1..-2]
            pipe.srem(redis_key, quoted)
            pipe.sadd(redis_key, unquoted)
          end
        end
      rescue StandardError => ex
        stats[:errors] << "#{label} (normalize): #{ex.message}"
        puts "  Error normalizing #{label}: #{ex.message}"
        OT.le "[DedupeInstances] Normalize error for #{redis_key}: #{ex.message}"
      end

      def print_next_steps(dry_run, action_count)
        return unless dry_run && action_count > 0

        puts <<~MESSAGE

          To execute changes, run:
            bin/ots migrations dedupe-instances --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Deduplicate & Normalize Class-Level Instance Collections

          Usage:
            bin/ots migrations dedupe-instances [options]

          Description:
            Cleans up JSON-quoted members in class-level sorted sets and
            sets (:instances, :expiration_timeline, :warnings_sent).

            Familia v2's serialize_value JSON-encodes identifiers. This
            command handles two cases:

            1. Deduplication: When both quoted ("abc") and raw (abc) forms
               exist, the quoted form is removed.
            2. Normalization: When only the quoted form exists (the raw
               form was never written), it is replaced with the raw form,
               preserving the original score for sorted sets.

          Models scanned:
            Customer, Organization, CustomDomain, Receipt, Secret,
            Feedback, OrganizationMembership (instances sorted sets)
            Receipt (expiration_timeline sorted set, warnings_sent set)

          Options:
            --run                 Execute changes (default is dry-run)
            --verbose, -v         Show each duplicate and normalized entry
            --help, -h            Show this help message

          Examples:
            # Preview (dry run)
            bin/ots migrations dedupe-instances

            # Execute changes
            bin/ots migrations dedupe-instances --run

            # Execute with verbose output
            bin/ots migrations dedupe-instances --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Deduplication removes quoted members when raw form exists
            - Normalization replaces quoted-only members with raw form
            - Sorted set scores are preserved during normalization
            - No data loss in either operation

        USAGE
        true
      end
    end

    register 'migrations dedupe-instances', DedupeInstancesCommand
  end
end
