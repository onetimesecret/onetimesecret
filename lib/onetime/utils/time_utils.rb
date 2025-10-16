# lib/onetime/utils/time_utils.rb

module Onetime
  module Utils
    module TimeUtils
      extend self

      using Familia::Refinements::TimeLiterals

      def extract_time_from_uuid_v7(uuid)
        # Remove hyphens and take first 12 hex characters
        timestamp_hex = uuid.delete('-')[0, 12]
        # Convert to milliseconds since Unix epoch
        timestamp_ms  = timestamp_hex.to_i(16)
        # Convert to Time object
        Time.at(timestamp_ms / 1000.0)
      end

      def time_to_uuid_v7_timestamp(time)
        # Convert to milliseconds since Unix epoch
        timestamp_ms = (time.to_f * 1000).to_i
        # Convert to 12-character hex string
        hex          = timestamp_ms.to_s(16).rjust(12, '0')
        # Format with hyphen after 8 characters
        "#{hex[0, 8]}-#{hex[8, 4]}"
      end

      def epochdom(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        time_parsed.utc.strftime('%b %d, %Y')
      end

      def natural_duration(duration_in_s)
        if duration_in_s <= 1.minute
          format('%d seconds', duration_in_s)
        elsif duration_in_s <= 1.hour
          format('%d minutes', duration_in_s.in_minutes)
        elsif duration_in_s <= 1.day
          format('%d hours', duration_in_s.in_hours)
        else
          format('%d days', duration_in_s.in_days)
        end
      end

      def natural_time(time_in_s)
        return if time_in_s.nil?

        val = Familia.now.to_i - time_in_s.to_i

        if val < 10
          result = 'a moment ago'
        elsif val < 40
          result = "about #{(val * 1.5).to_i.to_s.slice(0, 1)}0 seconds ago"
        elsif val < 60
          result = 'about a minute ago'
        elsif val < 60 * 1.3
          result = '1 minute ago'
        elsif val < 60 * 2
          result = '2 minutes ago'
        elsif val < 60 * 50
          result = "#{(val / 60).to_i} minutes ago"
        elsif val < 3600 * 1.4
          result = 'about 1 hour ago'
        elsif val < 3600 * (24 / 1.02)
          result = "about #{(val / 60 / 60 * 1.02).to_i} hours ago"
        elsif val < 3600 * 24 * 1.6
          result = Time.at(time_in_s.to_i).strftime('yesterday').downcase
        elsif val < 3600 * 24 * 7
          result = Time.at(time_in_s.to_i).strftime('on %A').downcase
        else
          weeks  = (val / 3600.0 / 24.0 / 7).to_i
          result = Time.at(time_in_s.to_i)
            .strftime("#{weeks} #{weeks == 1 ? 'week' : 'weeks'} ago")
            .downcase
        end
        result
      end
    end
  end
end
