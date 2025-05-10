# lib/onetime/initializers/boot.rb

require 'sysinfo'

module Onetime
  module Initializers
    @sysinfo = nil
    @conf = nil

    attr_reader :conf, :instance, :sysinfo

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
    # NOTE: Should be called last in the list of onetime helpers.
    #
    def boot!(mode = nil, connect_to_db = true)
      OT.mode = mode unless mode.nil?
      OT.env = ENV['RACK_ENV'] || 'production'
      # Default to diagnostics disabled
      # In test mode, this will be overridden by the value in test config
      OT.d9s_enabled = false

      @sysinfo ||= SysInfo.new.freeze

      # Sets a unique SHA hash every time this process starts. In a multi-
      # threaded environment (e.g. with Puma), this could different for
      # each thread.
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, Process.pid, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze

      # Normalize environment variables prior to loading the YAML config
      OT::Config.before_load

      # Loads the configuration and renders all value templates (ERB)
      raw_conf = OT::Config.load

      # Normalize the configruation and make it available to the rest
      # of the initializers (via OT.conf).
      @conf = OT::Config.after_load(raw_conf)

      # OT.conf is deeply frozen at this point which means that the
      # initializers are meant to read from it, set other values, but
      # not modify it.
      # TODO: Consider leaving unfrozen until the end of boot!

      # NOTE: We could benefit from tsort to make sure these
      # initializers are loaded in the correct order.
      load_locales
      set_global_secret
      set_rotated_secrets
      setup_authentication
      setup_diagnostics
      configure_domains
      configure_truemail
      prepare_emailers
      load_fortunes
      load_plans
      connect_databases if connect_to_db
      check_global_banner
      print_log_banner unless mode?(:test)

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil

    rescue OT::Problem => e
      OT.le "Problem booting: #{e}"
      OT.ld e.backtrace.join("\n")

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
      raise e unless mode?(:cli) # allows for debugging in the console

    rescue Redis::CannotConnectError => e
      OT.le "Cannot connect to redis #{Familia.uri} (#{e.class})"
      raise e unless mode?(:cli)

    rescue StandardError => e
      OT.le "Unexpected error `#{e}` (#{e.class})"
      OT.ld e.backtrace.join("\n")
      raise e unless mode?(:cli)
    end

    # Prints a banner with information about the current environment
    # and configuration.
    def print_log_banner
      site_config = OT.conf.fetch(:site) # if :site is missing we got real problems
      email_config = OT.conf.fetch(:emailer, {})
      redis_info = Familia.redis.info
      colonels = site_config.dig(:authentication, :colonels) || []

      OT.li "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 3}"
      OT.li "system: #{@sysinfo.platform} (#{RUBY_ENGINE} #{RUBY_VERSION} in #{OT.env})"
      OT.li "config: #{OT::Config.path}"
      OT.li "redis: #{redis_info['redis_version']} (#{Familia.uri.serverid})"
      OT.li "familia: v#{Familia::VERSION}"
      OT.li "i18n: #{OT.i18n_enabled}"
      OT.li "locales: #{@locales.keys.join(', ')}" if OT.i18n_enabled
      OT.li "diagnotics: #{OT.d9s_enabled}"

      if colonels.empty?
        OT.lw "colonels: No colonels configured"
      else
        OT.li "colonels: #{colonels.join(', ')}"
      end

      if site_config.dig(:plans, :enabled)
        OT.li "plans: #{OT::Plan.plans.keys}"
      end

      if site_config.key?(:authentication)
        OT.li "auth: #{site_config[:authentication].map { |k,v| "#{k}=#{v}" }.join(', ')}"
      end

      if email_config
        mail_settings = {
          mode: email_config[:mode],
          from: "'#{email_config[:fromname]} <#{email_config[:from]}>'",
          host: "#{email_config[:host]}:#{email_config[:port]}",
          region: email_config[:region],
          user: email_config[:user],
          tls: email_config[:tls],
          auth: email_config[:auth], # this is an smtp feature and not credentials
        }.map { |k,v| "#{k}=#{v}" }.join(', ')
        OT.li "mailer: #{@emailer}"
        OT.li "mail: #{mail_settings}"
      end

      # Log configuration sections that contain mapping data
      [:domains, :regions].each do |key|
        if site_config.key?(key)
          OT.li "#{key}: #{site_config[key].map { |k,v| "#{k}=#{v}" }.join(', ')}"
        end
      end

      # Log optional top-level configuration sections
      [:development, :experimental].each do |key|
        if config_value = OT.conf.fetch(key, false)
          OT.li "#{key}: #{config_value.map { |k,v| "#{k}=#{v}" }.join(', ')}"
        end
      end

      OT.li "secret options: #{OT.conf.dig(:site, :secret_options)}"
    end

  end
end
