# lib/onetime/helpers/initialization_helper.rb

require 'sysinfo'

module Onetime
  module InitializationHelper
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
    def boot!(mode = nil, db = true)
      OT.mode = mode unless mode.nil?
      OT.env = ENV['RACK_ENV'] || 'production'
      OT.d9s_enabled = false # diagnostics are disabled by default

      # Normalize environment variables prior to loading the YAML config
      OT::Config.before_load

      # Loads the configuration and renders all value templates (ERB)
      @conf = OT::Config.load

      # Normalize OT.conf
      OT::Config.after_load(@conf)

      Familia.uri = OT.conf[:redis][:uri]
      @sysinfo ||= SysInfo.new.freeze
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, $$, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze

      load_locales
      set_global_secret
      prepare_emailers
      load_fortunes
      load_plans
      connect_databases if db
      check_global_banner
      print_log_banner unless mode?(:test)

      @conf # return the config

    rescue OT::Problem => e
      OT.le "Problem booting: #{e}"
      OT.ld e.backtrace.join("\n")
      exit 1 unless mode?(:cli) # allows for debugging in the console

    rescue Redis::CannotConnectError => e
      OT.le "Cannot connect to redis #{Familia.uri} (#{e.class})"
      exit 10 unless mode?(:cli)

    rescue StandardError => e
      OT.le "Unexpected error `#{e}` (#{e.class})"
      OT.ld e.backtrace.join("\n")
      exit 99 unless mode?(:cli)
    end


    # Prints a banner with information about the current environment
    # and configuration.
    def print_log_banner
      site_config = OT.conf.fetch(:site) # if :site is missing we got real problems
      email_config = OT.conf.fetch(:emailer, {})
      redis_info = Familia.redis.info

      OT.li "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 3}"
      OT.li "system: #{@sysinfo.platform} (#{RUBY_ENGINE} #{RUBY_VERSION} in #{OT.env})"
      OT.li "config: #{OT::Config.path}"
      OT.li "redis: #{redis_info['redis_version']} (#{Familia.uri.serverid})"
      OT.li "familia: v#{Familia::VERSION}"
      OT.li "colonels: #{site_config.dig(:authentication, :colonels).join(', ')}"
      OT.li "i18n: #{OT.i18n_enabled}"
      OT.li "locales: #{@locales.keys.join(', ')}" if OT.i18n_enabled
      OT.li "diagnotics: #{OT.d9s_enabled}"

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
