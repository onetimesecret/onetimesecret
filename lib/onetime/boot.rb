# lib/onetime/boot.rb

require 'onetime/refinements/hash_refinements'

require_relative 'initializers'

module Onetime
  @conf = nil
  @env = nil
  @mode = :app
  @debug = nil

  class << self

    attr_accessor :mode, :d9s_enabled
    attr_writer :debug, :env, :global_secret
    attr_reader :conf, :instance, :i18n_enabled, :locales,
                :supported_locales, :default_locale, :fallback_locale,
                :global_banner, :rotated_secrets, :emailer, :first_boot

    using IndifferentHashAccess

    # Boot reads and interprets the configuration and applies it to the
    # relevant features and services. Must be called after applications
    # are loaded so that models have been required which is a pre-req
    # for attempting the database connection. Prior to that, Familia.members
    # is empty so we don't have any central list of models to work off
    # of.
    #
    # `mode` is a symbol, one of: :app, :cli, :test. It's used for logging
    # but otherwise doesn't do anything special (other than allow :cli to
    # continue even when it's cloudy with a chance of boot errors).
    #
    # When `db` is false, the database connections won't be initialized. This
    # is useful for testing or when you want to run code without necessary
    # loading all or any of the models.
    #
    def boot!(mode = nil, connect_to_db = true)
      prepare_onetime_namespace(mode)

      conf = OT::Config.setup

      # Run all registered initializers in TSort-determined order
      # Pass necessary context like mode and connect_to_db preference
      Onetime::Initializers::Registry.run_all!({
        mode: OT.mode,
        connect_to_db: connect_to_db,
      })

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil
    rescue => error
      handle_boot_error(error)
    end

    private

    def prepare_onetime_namespace(mode)
      @mode = mode unless mode.nil?
      @env = ENV['RACK_ENV'] || 'production'

      # Default to diagnostics disabled. FYI: in test mode, the test config
      # YAML has diagnostics enabled. But the DSN values are nil so it
      # doesn't get enabled even after loading config.
      @d9s_enabled = false

      # Sets a unique SHA hash every time this process starts. In a multi-
      # threaded environment (e.g. with Puma), this should be different for
      # each thread.
      @instance = [Process.pid.to_s, OT::VERSION.to_s].gibbler.freeze
    end

    def handle_boot_error(error)
      case error
      when OT::Problem
        OT.le "Problem booting: #{error}"
        OT.ld error.backtrace.join("\n")
      when Redis::CannotConnectError
        OT.le "Cannot connect to redis #{Familia.uri} (#{error.class})"
      when TSort::Cyclic
        # The detailed message from the registry's sorted_initializers will be part of e.message
        OT.le "Problem booting due to initializer dependency cycle: #{error.message}"
      else
        OT.le "Unexpected error `#{error}` (#{error.class})"
        OT.ld error.backtrace.join("\n")
      end

      # NOTE: Prefer `raise` over `exit` here. Previously we used
      # exit and it caused unexpected behaviour in tests, where
      # rspec for example would report all 5 examples passed even
      # though there were 30+ testcases defined in the file. There
      # were no log messages to indicate where the problem occurred
      # possibly because:
      #
      # 1. RSpec captures each example's STDOUT/STDERR and only prints it
      #    once the example finishes.
      # 2. Calling `exit` in the middle of an example kills the process
      #    immediately—any pending output (your `OT.le` message, buffered
      #    IO, etc.) never gets flushed back through RSpec's reporter.
      #
      # We were fortunate to find the issue via rspec. We had mocked
      # the connect_database method but also called the original:
      #
      # allow(Onetime).to receive(:connect_databases).and_call_original
      #
      raise error unless mode?(:cli) || mode?(:test)
    end

  end
end
