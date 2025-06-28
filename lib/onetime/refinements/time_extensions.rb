# lib/onetime/refinements/time_extensions.rb

module Onetime
  module TimeExtensions
    # rubocop:disable Layout/ExtraSpacing

    # Time unit constants
    PER_MICROSECOND = 0.000001
    PER_MILLISECOND = 0.001
    PER_MINUTE      = 60.0
    PER_HOUR        = 3600.0
    PER_DAY         = 86_400.0
    PER_WEEK        = 604_800.0
    PER_YEAR        = 31_536_000.0 # 365 days

    UNIT_METHODS = {
      'y' => :years,
      'year' => :years,
      'years' => :years,
      'w' => :weeks,
      'week' => :weeks,
      'weeks' => :weeks,
      'd' => :days,
      'day' => :days,
      'days' => :days,
      'h' => :hours,
      'hour' => :hours,
      'hours' => :hours,
      'm' => :minutes,
      'minute' => :minutes,
      'minutes' => :minutes,
      'ms' => :milliseconds,
      'millisecond' => :milliseconds,
      'milliseconds' => :milliseconds,
      'us' => :microseconds,
      'microsecond' => :microseconds,
      'microseconds' => :microseconds,
      'μs' => :microseconds,
    }.freeze

    refine Numeric do

      def microseconds = seconds * PER_MICROSECOND
      def milliseconds = seconds * PER_MILLISECOND
      def seconds      = self
      def minutes      = seconds * PER_MINUTE
      def hours        = seconds * PER_HOUR
      def days         = seconds * PER_DAY
      def weeks        = seconds * PER_WEEK
      def years        = seconds * PER_YEAR

      # Aliases with singular forms
      alias_method :microsecond, :microseconds
      alias_method :millisecond, :milliseconds
      alias_method :second,      :seconds
      alias_method :minute,      :minutes
      alias_method :hour,        :hours
      alias_method :day,         :days
      alias_method :week,        :weeks
      alias_method :year,        :years

      # Fun aliases
      alias_method :ms, :milliseconds
      alias_method :μs, :microseconds

      # Seconds -> other time units
      def in_years        = seconds / PER_YEAR
      def in_weeks        = seconds / PER_WEEK
      def in_days         = seconds / PER_DAY
      def in_hours        = seconds / PER_HOUR
      def in_minutes      = seconds / PER_MINUTE
      def in_milliseconds = seconds / PER_MILLISECOND
      def in_microseconds = seconds / PER_MICROSECOND
      # For semantic purposes
      def in_seconds      = seconds

      # Time manipulation
      def ago         = Time.now.utc - seconds
      def from_now    = Time.now.utc + seconds
      def before(time) = time - seconds
      def after(time)  = time + seconds
      def in_time = Time.at(seconds).utc

      # Milliseconds conversion
      def to_ms = seconds * 1000.0

      # Converts seconds to specified time unit
      #
      # @param u [String, Symbol] Unit to convert to
      # @return [Float] Converted time value
      def in_seconds(u = nil)
        return self unless u

        case UNIT_METHODS.fetch(u.to_s.downcase, nil)
        when :milliseconds then self * PER_MILLISECOND
        when :microseconds then self * PER_MICROSECOND
        when :minutes then self * PER_MINUTE
        when :hours then self * PER_HOUR
        when :days then self * PER_DAY
        when :weeks then self * PER_WEEK
        when :years then self * PER_YEAR
        else self
        end
      end

      # Converts the number to a human-readable string representation
      #
      # @return [String] A formatted string e.g. "1 day" or "10 seconds"
      #
      # @example
      #   10.to_humanize #=> "10 seconds"
      #   60.to_humanize #=> "1 minute"
      #   3600.to_humanize #=> "1 hour"
      #   86400.to_humanize #=> "1 day"
      def humanize
        gte_zero = positive? || zero?
        duration = (gte_zero ? self : abs) # let's keep it positive up in here
        text = case (s = duration.to_i)
        in 0..59       then "#{s} second#{'s' if s != 1}"
        in 60..3599    then "#{s  /= 60} minute#{'s' if s != 1}"
        in 3600..86_399 then "#{s /= 3600} hour#{'s' if s != 1}"
        else "#{s /= 86_400} day#{'s' if s != 1}"
        end
        gte_zero ? text : "#{text} ago"
      end

      # Converts the number to a human-readable byte representation using binary units
      #
      # @return [String] A formatted string of bytes, KiB, MiB, GiB, or TiB
      #
      # @example
      #   1024.to_bytes      #=> "1.00 KiB"
      #   2_097_152.to_bytes #=> "2.00 MiB"
      #   3_221_225_472.to_bytes #=> "3.00 GiB"
      #
      def to_bytes
        units = %w[B KiB MiB GiB TiB]
        size  = abs.to_f
        unit  = 0

        while size > 1024 && unit < units.length - 1
          size /= 1024
          unit += 1
        end

        format('%3.2f %s', size, units[unit])
      end

      # Calculates age of timestamp in specified unit from reference time
      #
      # @param unit [String, Symbol] Time unit ('days', 'hours', 'minutes', 'weeks')
      # @param from_time [Time, nil] Reference time (defaults to Time.now.utc)
      # @return [Float] Age in specified unit
      # @example
      #   timestamp = 2.days.ago.to_i
      #   timestamp.age_in(:days)         #=> ~2.0
      #   timestamp.age_in('hours')       #=> ~48.0
      #   timestamp.age_in(:days, 1.day.ago) #=> ~1.0
      def age_in(unit, from_time = nil)
        from_time ||= Time.now.utc
        age_seconds = from_time.to_f - to_f
        case UNIT_METHODS.fetch(unit.to_s.downcase, nil)
        when :days then age_seconds / PER_DAY
        when :hours then age_seconds / PER_HOUR
        when :minutes then age_seconds / PER_MINUTE
        when :weeks then age_seconds / PER_WEEK
        else age_seconds
        end
      end

      # Convenience methods for `age_in(unit)` calls.
      #
      # @param from_time [Time, nil] Reference time (defaults to Time.now.utc)
      # @return [Float] Age in days
      # @example
      #   timestamp.days_old    #=> 2.5
      def days_old(*) = age_in(:days, *)
      def hours_old(*) = age_in(:hours, *)
      def minutes_old(*) = age_in(:minutes, *)
      def weeks_old(*) = age_in(:weeks, *)
      def months_old(*) = age_in(:months, *)
      def years_old(*) = age_in(:years, *)

      # Checks if timestamp is older than specified duration in seconds
      #
      # @param duration [Numeric] Duration in seconds to compare against
      # @return [Boolean] true if timestamp is older than duration
      # @note Both older_than? and newer_than? can return false when timestamp
      #   is within the same second. Use within? to check this case.
      #
      # @example
      #   Time.now.older_than?(1.second)    #=> false
      def older_than?(duration)
        self < (Time.now.utc.to_f - duration)
      end

      # Checks if timestamp is newer than specified duration in the future
      #
      # @example
      #   Time.now.newer_than?(1.second)    #=> false
      def newer_than?(duration)
        self > (Time.now.utc.to_f + duration)
      end

      # Checks if timestamp is within specified duration of now (past or future)
      #
      # @param duration [Numeric] Duration in seconds to compare against
      # @return [Boolean] true if timestamp is within duration of now
      # @example
      #   30.minutes.ago.to_i.within?(1.hour)     #=> true
      #   30.minutes.from_now.to_i.within?(1.hour) #=> true
      #   2.hours.ago.to_i.within?(1.hour)        #=> false
      def within?(duration)
        (self - Time.now.utc.to_f).abs <= duration
      end

    end

    refine String do
      # Converts string time representation to seconds
      #
      # @example
      #   "60m".in_seconds #=> 3600.0
      #   "2.5h".in_seconds #=> 9000.0
      #
      # @return [Float, nil] Time in seconds or nil if invalid
      def in_seconds
        q, u = scan(/([\d.]+)([smh])?/).flatten
        return nil unless q

        q   = q.to_f
        u ||= 's'
        q.in_seconds(u)
      end
    end

    # rubocop:enable Layout/ExtraSpacing
  end
end
