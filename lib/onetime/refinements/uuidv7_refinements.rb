# lib/onetime/refinements/uuidv7_refinements.rb

module Onetime
  # UUIDv7 Refinements for SecureRandom, String, and Time
  #
  # Usage:
  #
  #   using Onetime::UUIDv7Refinements
  #
  #   uuid = SecureRandom.uuid_v7
  #   time = SecureRandom.extract_time_from_uuid_v7(uuid)
  #   timestamp = SecureRandom.time_to_uuid_v7_timestamp(time)
  #
  module UUIDv7Refinements
    refine SecureRandom.singleton_class do
      def uuid_v7_from(time)
        # Generate UUID v7 from specific time
        timestamp_ms   = (time.to_f * 1000).to_i
        hex            = timestamp_ms.to_s(16).rjust(12, '0')
        timestamp_part = "#{hex[0, 8]}-#{hex[8, 4]}-7"
        random_part    = SecureRandom.hex(9)
        "#{timestamp_part}#{random_part[0, 3]}-#{random_part[3, 4]}-#{random_part[7, 12]}"
      end
    end

    refine String do
      def uuid_v7_time
        return nil unless uuid_v7?

        timestamp_hex = delete('-')[0, 12]
        timestamp_ms  = timestamp_hex.to_i(16)
        Time.at(timestamp_ms / 1000.0)
      end

      def uuid_v7?
        match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
      end
    end

    refine Time do
      def to_uuid_v7
        SecureRandom.uuid_v7_from(self)
      end
    end
  end
end
