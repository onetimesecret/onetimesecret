# lib/onetime/classmethods.rb

# Usage:
# module Onetime
#   extend EnvironmentHelper
# end
#
# Environment detection and normalization
module Onetime
  module ClassMethods
    @env = nil
    @mode = :app
    @debug = nil

    # d9s: diagnostics is a boolean flag. If true, it will enable Sentry
    @d9s_enabled = false

    attr_accessor :mode, :env, :d9s_enabled
    attr_writer :debug

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
      when 'test' then 'test'
      else
        # Valid environment names pass through, unknown values become 'production'
        %w[development production test staging].include?(env) ? env : 'production'
      end
    end

    def now
      Time.now.utc
    end

    def with_diagnostics(&)
      return unless Onetime.d9s_enabled
      yield # call the block in its own context
    end

    def debug
      @debug ||= ENV['ONETIME_DEBUG'].to_s.match?(/^(true|1)$/i)
    end

    def debug?
      !!debug # force a boolean
    end

    def mode?(guess)
      @mode.to_s == guess.to_s
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

    # Convenience methods for environment checking
    def production?; env == 'production'; end
    def development?; env == 'development'; end
    def test?; env == 'test'; end
    def staging?; env == 'staging'; end
  end
end
