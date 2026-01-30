# migrations/2026-01-28/lib/shared/uuid_v7_generator.rb
#
# frozen_string_literal: true

require 'securerandom'
require 'digest'

module Migration
  module Shared
    # Generates UUIDv7 identifiers from timestamps and derives external IDs.
    #
    # Provides standalone UUID generation without external dependencies.
    # Matches the identifier generation logic from enrich_with_identifiers.rb.
    #
    # Usage:
    #   gen = UuidV7Generator.new
    #   objid = gen.generate_from_timestamp(1706140800)
    #   extid = gen.derive_extid(objid, prefix: 'ur')
    #
    class UuidV7Generator
      # Generate UUID v7 from Unix timestamp (seconds).
      #
      # Note: Records sharing the same second will have random (not deterministic)
      # sort order within that second. Sub-second precision not preserved.
      #
      # @param timestamp_seconds [Numeric] Unix timestamp in seconds
      # @return [String] UUID v7 string (e.g., "0194d8e0-1234-7abc-8def-0123456789ab")
      #
      def generate_from_timestamp(timestamp_seconds)
        # Convert to milliseconds (UUID v7 uses 48-bit ms timestamp)
        timestamp_ms = (timestamp_seconds.to_f * 1000).to_i

        # Encode timestamp as 48-bit hex (12 hex chars)
        hex = timestamp_ms.to_s(16).rjust(12, '0')

        # Generate random parts
        random_bytes = SecureRandom.random_bytes(10)
        rand_hex = random_bytes.unpack1('H*')

        # Construct UUID parts per RFC 9562
        time_hi = hex[0, 8]                                     # bits 0-31 of timestamp
        time_mid = hex[8, 4]                                    # bits 32-47 of timestamp
        ver_rand = '7' + rand_hex[0, 3]                         # version 7 + 12 random bits

        # Variant: mask to 10xxxxxx per RFC 9562
        variant_byte = (rand_hex[3, 2].to_i(16) & 0x3F) | 0x80
        variant = variant_byte.to_s(16).rjust(2, '0') + rand_hex[5, 2]

        node = rand_hex[7, 12] # Uses indices 7-18

        "#{time_hi}-#{time_mid}-#{ver_rand}-#{variant}-#{node}"
      end

      # Derive external ID from UUID using deterministic hashing.
      #
      # Matches Familia v2.0.0-pre12 approach for generating external IDs.
      #
      # @param uuid_string [String] UUID string (with or without hyphens)
      # @param prefix [String] Model-specific prefix (e.g., 'ur', 'cd')
      # @return [String] External ID (e.g., "ur0abc123def456...")
      #
      def derive_extid(uuid_string, prefix:)
        # Normalize UUID to hex (remove hyphens)
        normalized_hex = uuid_string.delete('-')

        # Create seed from the hex string
        seed = Digest::SHA256.digest(normalized_hex)

        # Initialize PRNG with the seed
        prng = Random.new(seed.unpack1('Q>'))

        # Generate 16 bytes of deterministic output
        random_bytes = prng.bytes(16)

        # Encode as base36 string (25 chars)
        external_part = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')

        "#{prefix}#{external_part}"
      end

      # Generate both objid and extid from timestamp.
      #
      # @param timestamp_seconds [Numeric] Unix timestamp
      # @param prefix [String] ExtID prefix for this model
      # @return [Array<String, String>] [objid, extid]
      #
      def generate_identifiers(timestamp_seconds, prefix:)
        objid = generate_from_timestamp(timestamp_seconds)
        extid = derive_extid(objid, prefix: prefix)
        [objid, extid]
      end
    end
  end
end
