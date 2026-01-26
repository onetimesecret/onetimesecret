# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'digest'

module Transformers
  # Shared functionality for all model transformers.
  # Provides UUIDv7 generation, extid derivation, and stats tracking helpers.
  class BaseTransformer
    attr_reader :stats

    def initialize(context)
      @context = context
      @stats   = default_stats
    end

    # Override in subclasses to provide model-specific default stats
    def default_stats
      { scanned: 0, transformed: 0, skipped: 0 }
    end

    # Route a record - subclasses must implement
    def route(record, key)
      raise NotImplementedError, "#{self.class}#route must be implemented"
    end

    protected

    # Access shared mappings from context
    def email_to_objid
      @context[:email_to_objid]
    end

    def email_to_org_objid
      @context[:email_to_org_objid]
    end

    def email_to_org_data
      @context[:email_to_org_data]
    end

    def email_to_membership
      @context[:email_to_membership]
    end

    def domainid_to_objid
      @context[:domainid_to_objid]
    end

    # Stats helpers shared across transformers
    def skip_index_key
      @context[:stats][:indexes][:skipped] += 1
      nil
    end

    def skip_other_key
      @context[:stats][:other][:skipped] += 1
      nil
    end

    # Parse created timestamp from record (float seconds since epoch)
    def parse_created_time(created_value)
      return nil if created_value.nil? || created_value.to_s.empty?

      Time.at(created_value.to_f)
    rescue ArgumentError
      nil
    end

    # Generate UUIDv7 from a specific time (preserves historical ordering)
    # Standalone implementation copied from lib/onetime/refinements/uuidv7_refinements.rb
    # to avoid requiring OT boot.
    def uuid_v7_from(time)
      timestamp_ms   = (time.to_f * 1000).to_i
      hex            = timestamp_ms.to_s(16).rjust(12, '0')
      timestamp_part = "#{hex[0, 8]}-#{hex[8, 4]}-7"
      base_uuid      = generate_base_uuid_v7
      base_parts     = base_uuid.split('-')
      "#{timestamp_part}#{base_parts[2][1..]}-#{base_parts[3]}-#{base_parts[4]}"
    end

    # Generate a base UUIDv7 with current time (used for random portion extraction)
    def generate_base_uuid_v7
      timestamp_ms = (Time.now.to_f * 1000).to_i
      random_bytes = SecureRandom.random_bytes(10).bytes

      uuid_bytes = [
        (timestamp_ms >> 40) & 0xFF,
        (timestamp_ms >> 32) & 0xFF,
        (timestamp_ms >> 24) & 0xFF,
        (timestamp_ms >> 16) & 0xFF,
        (timestamp_ms >> 8) & 0xFF,
        timestamp_ms & 0xFF,
        (0x70 | (random_bytes[0] & 0x0F)),  # version 7
        random_bytes[1],
        (0x80 | (random_bytes[2] & 0x3F)),  # variant 10xx
        random_bytes[3],
        random_bytes[4],
        random_bytes[5],
        random_bytes[6],
        random_bytes[7],
        random_bytes[8],
        random_bytes[9],
      ].pack('C*')

      hex = uuid_bytes.unpack1('H*')
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    # Derive deterministic external ID from UUID
    # Matches Familia v2's derive_external_identifier format: {prefix}{base36_id}
    def derive_extid_from_uuid(uuid_string, prefix: 'ext')
      normalized_hex = uuid_string.delete('-')
      seed           = Digest::SHA256.digest(normalized_hex)
      prng           = Random.new(seed.unpack1('Q>'))
      random_bytes   = prng.bytes(16)
      external_part  = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')
      "#{prefix}#{external_part}"
    end

    # Generate objid from optional created timestamp (falls back to Time.now)
    def generate_objid(created_time = nil)
      time = created_time || Time.now
      uuid_v7_from(time)
    end
  end
end
