# lib/onetime/class_methods.rb
#
# frozen_string_literal: true

require 'semantic_logger'

require_relative 'logger_methods'

# Usage:
# module Onetime
#   extend EnvironmentHelper
# end
#
# Environment detection and normalization
module Onetime
  module ClassMethods
    prepend Onetime::LoggerMethods

    @env   = nil
    @mode  ||= :app
    @debug = nil
    @logger = nil

    attr_accessor :mode, :env
    attr_writer :debug

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
    # Uses Familia.now.utc.to_f which returns seconds as a Float with subsecond
    # precision, then multiplies by 1,000,000 and converts to integer. While
    # generally reliable, this approach may have slight performance overhead
    # compared to direct system clock access and could theoretically suffer
    # from floating-point precision limitations with very large timestamp
    # values (though not practically relevant until ~2285 CE).
    #
    # @return [Integer] Microseconds since Unix epoch (January 1, 1970
    #   00:00:00 UTC)
    #   Range: Same as hnowµs but computed via different path
    #   Precision: Limited by Familia.now precision and floating-point
    #   conversion
    #
    # @note This method is suitable for:
    #   - General-purpose timestamping where maximum precision isn't critical
    #   - Legacy code compatibility where Familia.now patterns are established
    #   - Situations where Process.clock_gettime isn't available (very old
    #     Ruby versions)
    #
    # @note Considerations:
    #   - Slightly slower than hnowµs due to floating-point arithmetic
    #   - Precision depends on Familia.now implementation (usually microsecond
    #     or better)
    #   - Result should be identical to hnowµs under normal circumstances
    #   - May show small variations from hnowµs due to different code paths
    #
    # @example
    #   nowµs  #=> 1716825600123456
    #   nowµs  #=> 1716825600123458 (called shortly after)
    #
    # @see Familia.now Ruby documentation for underlying time source
    def nowµs
      (Familia.now * 1_000_000).to_i
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
    #   Precision: Full system precision (accessible via #nsec, #usec methods)
    #   Timezone: Always UTC (Coordinated Universal Time)
    #
    # @note This method is optimal for:
    #   - Human-readable time formatting and display
    #   - Date/time arithmetic operations (adding days, months, etc.)
    #   - Time zone conversions and calculations
    #   - Integration with Rails/ActiveSupport time helpers
    #   - Situations requiring Time object methods (#strftime, #year, #month, etc.)
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
    #
    # @see Time Ruby documentation for full Time object capabilities
    def now
      Familia.now
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

    # Returns the current monotonic time in microseconds for duration
    # measurements. Uses CLOCK_MONOTONIC which is immune to system clock
    # adjustments (NTP, DST, manual changes) making it ideal for measuring
    # elapsed time intervals.
    #
    # Delegates to Familia.now_in_μs which uses Process.clock_gettime with
    # CLOCK_MONOTONIC. This clock always moves forward at a constant rate
    # and is perfect for performance measurements, timeouts, and duration
    # tracking.
    #
    # @return [Integer] Monotonic time in microseconds
    #   Range: Arbitrary starting point (typically system boot time), only
    #     meaningful for computing time differences
    #   Precision: 1 microsecond (1/1,000,000 second)
    #
    # @note This method is optimal for:
    #   - Measuring request/operation duration
    #   - Performance profiling and benchmarking
    #   - Timeout calculations
    #   - Rate limiting with time windows
    #   - Any scenario requiring reliable time differences
    #
    # @note DO NOT use for:
    #   - Timestamps that need to represent actual wall clock time
    #   - Values that need to be stored and compared across system reboots
    #   - Synchronization with external systems or databases
    #
    # @note Key differences from hnowµs:
    #   - hnowµs: CLOCK_REALTIME (wall clock) - for timestamps
    #   - now_in_μs: CLOCK_MONOTONIC (steady clock) - for durations
    #
    # @example Measuring operation duration
    #   start = Onetime.now_in_μs
    #   # ... perform operation ...
    #   duration = Onetime.now_in_μs - start  # microseconds elapsed
    #
    # @example Request timing in middleware
    #   start = Onetime.now_in_μs
    #   status, headers, body = @app.call(env)
    #   duration = Onetime.now_in_μs - start
    #   logger.info "Request completed", duration: duration
    #
    # @see Familia.now_in_μs Underlying implementation
    # @see Process.clock_gettime Ruby documentation for clock types
    def now_in_μs
      Familia.now_in_μs
    end
    alias now_in_microseconds now_in_μs

    # Logging methods using SemanticLogger for structured logging
    #
    # All methods now use SemanticLogger with consistent output format.
    # Messages without payload will log with empty payload hash.
    #
    # Basic usage:
    #   Onetime.li "User logged in"  # -> SemanticLogger with empty payload
    #   Onetime.le "Authentication failed"
    #
    # Structured logging (recommended):
    #   Onetime.li "User logged in", user_id: user.id, ip: request.ip
    #   Onetime.le "Auth failed", reason: :invalid_password
    #
    # Exception logging:
    #   Onetime.le "Operation failed", exception: ex, context: value
    #   Onetime.le "Login failed", exception: ex, email: email, ip: ip
    #
    # Category-aware logging via thread-local:
    #   Thread.current[:log_category] = 'Auth'
    #   Onetime.ld "Processing login", email: email
    #
    def info(*msgs, **payload)
      return unless mode?(:app) || mode?(:cli) # can reduce output in tryouts

      logger.info(msgs.join(' '), payload)
    end

    def li(*msgs, **payload)
      logger.info(msgs.join(' '), payload)
    end

    def lw(*msgs, **payload)
      logger.warn(msgs.join(' '), payload)
    end

    def le(*msgs, exception: nil, **payload)
      # If exception is provided, use SemanticLogger's exception handling
      if exception.is_a?(Exception)
        msg = msgs.join(' ')
        msg = "#{exception.class.name}" if msg.empty?
        logger.error(msg, exception, payload)
      else
        logger.error(msgs.join(' '), payload)
      end
    end

    def ld(*msgs, **payload)
      return unless Onetime.debug

      logger.debug(msgs.join(' '), payload)
    end

    # Returns the appropriate SemanticLogger instance for the current context.
    # Defaults to 'App' category unless overridden via thread-local variable.
    #
    # Used by Onetime.ld/le/li/lw methods for bootstrap and early-stage logging
    # before all loggers are configured. Defaults to 'App' category unless
    # overridden via thread-local variable.
    #
    # Note: This is distinct from Onetime::LoggerMethods#logger which provides
    # automatic category inference for instance methods in classes.
    #
    # @example Module-level logging
    #   Onetime.ld "Bootstrap message"  # → SemanticLogger['App']
    #
    # @example With thread-local override
    #   Thread.current[:log_category] = 'Auth'
    #   Onetime.li "Auth message"  # → SemanticLogger['Auth']
    #
    # @example
    #   Thread.current[:log_category] = 'Auth'
    #   logger.info "Processing login"  # Uses SemanticLogger['Auth']
    #
    def logger
      return @logger if @logger

      super # i.e. Logging#logger
    end

    def with_diagnostics(&)
      return unless Onetime.d9s_enabled

      yield # call the block in its own context
    end

    def debug
      return @debug unless @debug.nil?
      @debug = Onetime::Utils.yes?(ENV['ONETIME_DEBUG'])
    end

    def stdout(prefix, msg)
      return if STDOUT.closed?

      stamp   = Familia.now.to_i
      logline = format('%s(%s): %s', prefix, stamp, msg)
      STDOUT.puts(logline)
    end
    private :stdout

    def stderr(prefix, msg)
      return if STDERR.closed?

      stamp   = Familia.now.to_i
      logline = format('%s(%s): %s', prefix, stamp, msg)
      warn(logline)
    end
    private :stderr

    # Warn about legacy logging usage (only once per file to avoid spam)
    def warn_about_legacy_logging
      caller_file = caller(2..2).first&.split(':')&.first
      @legacy_log_warnings ||= Set.new

      return if @legacy_log_warnings.include?(caller_file)
      @legacy_log_warnings << caller_file

      logger.warn "Legacy logging detected - use keyword arguments for structured logging", {
        file: caller_file,
        migration_guide: 'docs/logging-migration-guide.md'
      }
    end
    private :warn_about_legacy_logging

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
      in_environment?(%w[prod production], &)
    end

    def development?(&)
      in_environment?(%w[dev development], &)
    end

    def testing?(&)
      in_environment?(%w[test testing], &)
    end

    def staging?(&)
      in_environment?(%w[stage staging], &)
    end

    def env?(guess)
      env.eql?(guess.to_s.downcase)
    end

    # Returns the normalized application environment
    # Defaults to 'production' when uncertain for maximum security
    # @return [String] environment name
    def env
      case ENV.fetch('RACK_ENV', 'production').downcase
      when 'dev', 'development' then 'development'
      when 'stage', 'staging'   then 'staging'
      when 'test', 'testing' then 'testing'
      when 'prod', 'production' then 'production'
      else
        raise "Unknown environment: #{ENV.fetch('RACK_ENV', nil)}"
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
    #   in_environment?(['development', 'dev'])  #=> true/false
    #
    # @example With block execution
    #   in_environment?(['production']) { setup_monitoring }
    #
    # @example Block with conditional execution
    #   in_environment?(['development', 'staging']) do
    #     puts "Running in non-production environment"
    #     enable_debug_logging
    #   end
    #
    def in_environment?(patterns, &block)
      result = patterns.any? { env == it }
      block&.call if result
      result
    end
  end
end
