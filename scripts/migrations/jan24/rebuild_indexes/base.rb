# frozen_string_literal: true

# Base module for index rebuilding operations.
# Provides shared functionality for all model-specific index builders.

module IndexRebuilder
  # External ID prefixes (from Familia v2 models)
  # Format: prefix + first 16 chars of objid (no dashes)
  EXTID_PREFIXES = {
    customer: 'ur',
    organization: 'on',
    customdomain: 'cd',
    receipt: 'rc',
  }.freeze

  # Base class with shared utilities for index building
  class Base
    attr_reader :valkey, :dry_run, :stats

    def initialize(valkey:, dry_run:, stats:)
      @valkey  = valkey
      @dry_run = dry_run
      @stats   = stats
    end

    # Generate external ID in the correct format
    # @param prefix [String] Model prefix (ur, on, cd, rc)
    # @param objid [String] Object identifier (UUID format)
    # @return [String] External ID (prefix + 16 hex chars)
    def generate_extid(prefix, objid)
      # Remove dashes from UUID and take first 16 chars
      clean_id = objid.to_s.delete('-')[0, 16]
      "#{prefix}#{clean_id}"
    end

    # Build an instances sorted set for a model
    # @param model_prefix [String] Key prefix for scanning (e.g., 'customer')
    # @param index_name [String] Index name for the instances key
    def build_instances_set(model_prefix, index_name)
      puts "  Building #{index_name}:instances..."

      instances_key = "#{index_name}:instances"
      count         = 0

      cursor = '0'
      loop do
        cursor, keys = valkey.scan(cursor, match: "#{model_prefix}:*:object", count: 1000)

        keys.each do |key|
          # Extract objid from key
          objid = key.split(':')[1]

          # Get created timestamp for score (fall back to current time)
          created = valkey.hget(key, 'created') || valkey.hget(key, 'joined_at') || Time.now.to_f

          unless dry_run
            valkey.zadd(instances_key, created.to_f, objid)
          end
          count += 1
        end

        break if cursor == '0'
      end

      puts "    Added #{count} entries to #{instances_key}"
      stats[:instances][:created] += count
    end

    # Scan keys matching a pattern and yield each key
    # @param pattern [String] Key pattern to match
    # @yield [key] Each matching key
    def scan_keys(pattern, &)
      cursor = '0'
      loop do
        cursor, keys = valkey.scan(cursor, match: pattern, count: 1000)
        keys.each(&)
        break if cursor == '0'
      end
    end
  end
end
