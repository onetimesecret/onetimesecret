# lib/onetime/class_methods.rb

# Usage:
# module Onetime
#   extend EnvironmentHelper
# end
#
# Environment detection and normalization
module Onetime
  @env = nil
  @mode = :app
  @debug = nil

  module ClassMethods
    attr_accessor :mode
    attr_writer :debug, :env

    # Replaces the global configuration instance with the provided data.
    def replace_config!(other)
      # TODO: Validate the new configuration data before replacing it
      self.conf = other
    end

    # Returns the current wall clock time as microseconds since Unix epoch
    # using the system's high-precision clock interface. This method provides
    # the most accurate and consistent timestamp available on the platform.
    #
    # Uses Process.clock_gettime with CLOCK_REALTIME, which directly
    # interfaces with the system's realtime clock and typically offers better
    # precision and performance than Time-based alternatives. The
    # CLOCK_REALTIME source represents actual wall clock time and is suitable
    # for timestamps that need to be compared across system restarts or with
    # external systems.
    #
    # @return [Integer] Microseconds since Unix epoch (January 1, 1970
    #   00:00:00 UTC)
    #   Range: ~1,600,000,000,000,000 to ~4,100,000,000,000,000 (current
    #   era to ~2100 CE)
    #   Precision: 1 microsecond (1/1,000,000 second)
    #
    # @note This method is optimal for:
    #   - Redis sorted set scores (avoids floating-point precision issues)
    #   - High-frequency timestamp generation in tests
    #   - Performance-critical timestamp operations
    #   - Cross-platform consistent precision
    #
    # @note Platform considerations:
    #   - Linux: True microsecond or nanosecond precision typically available
    #   - macOS: Usually microsecond precision, nanosecond may be simulated
    #   - Windows: Precision varies, typically millisecond to microsecond
    #
    # @example
    #   hnowµs  #=> 1716825600123456
    #   hnowµs  #=> 1716825600123457 (called 1 microsecond later)
    #
    # @see Process.clock_gettime Ruby documentation for underlying
    #   implementation
    # @since Ruby 2.1.0 (when Process.clock_gettime was introduced)
    def hnowµs
      Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond)
    end

    # Returns the current UTC time as microseconds since Unix epoch, computed
    # from Ruby's Time object. This method converts the high-precision
    # floating-point time representation to an integer microsecond count.
    #
    # Uses Time.now.utc.to_f which returns seconds as a Float with subsecond
    # precision, then multiplies by 1,000,000 and converts to integer. While
    # generally reliable, this approach may have slight performance overhead
    # compared to direct system clock access and could theoretically suffer
    # from floating-point precision limitations with very large timestamp
    # values (though not practically relevant until ~2285 CE).
    #
    # @return [Integer] Microseconds since Unix epoch (January 1, 1970
    #   00:00:00 UTC)
    #   Range: Same as hnowµs but computed via different path
    #   Precision: Limited by Time.now precision and floating-point
    #   conversion
    #
    # @note This method is suitable for:
    #   - General-purpose timestamping where maximum precision isn't critical
    #   - Legacy code compatibility where Time.now patterns are established
    #   - Situations where Process.clock_gettime isn't available (very old
    #     Ruby versions)
    #
    # @note Considerations:
    #   - Slightly slower than hnowµs due to floating-point arithmetic
    #   - Precision depends on Time.now implementation (usually microsecond
    #     or better)
    #   - Result should be identical to hnowµs under normal circumstances
    #   - May show small variations from hnowµs due to different code paths
    #
    # @example
    #   nowµs  #=> 1716825600123456
    #   nowµs  #=> 1716825600123458 (called shortly after)
    #
    # @see Time.now Ruby documentation for underlying time source
    def nowµs
      (Time.now.utc.to_f * 1_000_000).to_i
    end

    # Returns the current time as a Time object in UTC timezone. This is the
    # standard Ruby approach for obtaining timezone-normalized time objects
    # suitable for date/time arithmetic, formatting, and general temporal
    # operations.
    #
    # The returned Time object contains full precision available from the
    # system (typically microsecond, potentially nanosecond) and provides
    # rich functionality for time manipulation, comparison, and formatting
    # operations.
    #
    # @return [Time] Time object representing current UTC time
    #   Precision: Full system precision (accessible via #nsec, #usec
    #   methods)
    #   Timezone: Always UTC (Coordinated Universal Time)
    #
    # @note This method is optimal for:
    #   - Human-readable time formatting and display
    #   - Date/time arithmetic operations (adding days, months, etc.)
    #   - Time zone conversions and calculations
    #   - Integration with Rails/ActiveSupport time helpers
    #   - Situations requiring Time object methods (#strftime, #year,
    #     #month, etc.)
    #
    # @note Avoid for:
    #   - Redis sorted set scores (use hnowµs or nowµs instead)
    #   - Numeric timestamp comparisons (conversion overhead)
    #   - High-frequency operations where integer timestamps suffice
    #
    # @example
    #   now  #=> 2024-05-27 14:26:40.123456 UTC
    #   now.to_i  #=> 1716825600 (seconds since epoch)
    #   now.usec  #=> 123456 (microsecond component)
    #   now.strftime('%Y-%m-%d %H:%M:%S')  #=> "2024-05-27 14:26:40"
    #
    # @see Time Ruby documentation for full Time object capabilities
    def now
      Time.now.utc
    end

    # Returns the current wall clock time as a floating-point number of
    # seconds since the Unix epoch, using the system's high-precision clock
    # interface.
    #
    # This method utilizes Process.clock_gettime with CLOCK_REALTIME and
    # :float_second, providing sub-second precision suitable for performance
    # measurements, time calculations, and scenarios where fractional seconds
    # are required.
    #
    # @return [Float] Seconds since Unix epoch (January 1, 1970 00:00:00
    #   UTC), with sub-second precision
    #
    # @note This method is optimal for:
    #   - High-precision time interval calculations
    #   - Profiling and benchmarking code execution
    #   - Scenarios requiring floating-point timestamps
    #
    # @note Platform considerations:
    #   - Precision and accuracy depend on the underlying operating system
    #     and hardware
    #   - Typically provides microsecond or better precision on modern
    #     systems
    #
    # @example
    #   hnow  #=> 1716825600.123456
    #   hnow  #=> 1716825600.123457 (called microseconds later)
    #
    # @see Process.clock_gettime Ruby documentation for further details
    def hnow
      Process.clock_gettime(Process::CLOCK_REALTIME, :float_second)
    end

    def info(*msgs)
      return unless mode?(:app) || mode?(:cli) # can reduce output in tryouts
      msg = msgs.join("#{$/}")
      stdout("I", msg)
    end

    def li(*msgs)
      msg = msgs.join("#{$/}")
      stdout("I", msg)
    end

    def lw(*msgs)
      msg = msgs.join("#{$/}")
      stdout("W", msg)
    end

    def le(*msgs)
      msg = msgs.join("#{$/}")
      stderr("E", msg)
    end

    def ld(*msgs)
      return unless Onetime.debug
      msg = msgs.join("#{$/}")
      stderr("D", msg)
    end

    def stdout(prefix, msg)
      return if STDOUT.closed?

      stamp = Time.now.to_i
      logline = "%s(%s): %s" % [prefix, stamp, msg]
      STDOUT.puts(logline)
    end

    def stderr(prefix, msg)
      return if STDERR.closed?

      stamp = Time.now.to_i
      logline = "%s(%s): %s" % [prefix, stamp, msg]
      STDERR.puts(logline)
    end

    def with_diagnostics(&)
      return unless Onetime.d9s_enabled
      yield # call the block in its own context
    end

    def debug
      @debug ||= ENV['ONETIME_DEBUG'].to_s.match?(/^(true|1)$/i)
    end

    # Returns debug status and optionally executes block if enabled.
    #
    # @example Basic usage
    #   debug?  #=> true/false
    #
    # @example With block execution
    #   debug? { enable_verbose_logging }
    def debug?(&block)
      result = !!debug
      block&.call if result
      result
    end

    # Compares current mode and optionally executes block if matched.
    #
    # @example Basic usage
    #   mode?(:cli)  #=> true/false
    #
    # @example With block execution
    #   mode?(:cli) { wait_for_interactive_answer }
    def mode?(guess, &block)
      result = @mode.to_s == guess.to_s
      block&.call if result
      result
    end

    # Convenience methods for environment checking
    def production?(&)
      env_matches?(%w[prod production], &)
    end

    def development?(&)
      env_matches?(%w[dev development], &)
    end

    def testing?(&)
      env_matches?(%w[test testing], &)
    end

    def staging?(&)
      env_matches?(%w[stage staging], &)
    end

    # Returns the normalized application environment
    # Defaults to 'production' when uncertain for maximum security
    # @return [String] environment name
    def env
      env = ENV['RACK_ENV'] || 'production'

      # Normalize abbreviated environment names
      case env
      when 'dev'  then 'development'
      when 'prod' then 'production'
      when 'stage', 'staging' then 'staging'
      when 'test', 'testing' then 'testing'
      else
        # Valid environment names pass through, unknown values become 'production'
        %w[development production testing staging].include?(env) ? env : 'production'
      end
    end

    private

    # Checks if the current environment matches any of the given patterns.
    # Optionally executes a block if a match is found.
    #
    # @param patterns [Array<String>] Environment names to match against
    # @param block [Proc, nil] Optional block executed on match
    # @return [Boolean] true if any pattern matches current environment
    #
    # @note Requires Ruby 2.7+ for _1 numbered parameter syntax
    #
    # @example Basic matching
    #   env_matches?(['development', 'dev'])  #=> true/false
    #
    # @example With block execution
    #   env_matches?(['production']) { setup_monitoring }
    #
    # @example Block with conditional execution
    #   env_matches?(['development', 'staging']) do
    #     puts "Running in non-production environment"
    #     enable_debug_logging
    #   end
    #
    def env_matches?(patterns, &block)
      result = patterns.any? { env == _1 }
      block&.call if result
      result
    end

    # Replaces the global configuration instance. This method is private to
    # prevent external modification of the shared configuration state
    # after initialization.
    def conf=(value)
      @conf = value
    end
  end

  extend ClassMethods
end
