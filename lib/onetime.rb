# lib/onetime.rb

require 'bundler/setup'
require 'securerandom'

require 'truemail'

require 'erb'
require 'syslog'

require 'encryptor'
require 'bcrypt'

require 'sendgrid-ruby'

require 'rack'
require 'otto'
require 'gibbler/mixins'
require 'familia'
require 'storable'
require 'sysinfo'

require_relative 'onetime/core_ext'
require_relative 'onetime/refinements/horreum_refinements'

# Ensure immediate flushing of stdout to improve real-time logging visibility.
# This is particularly useful in development and production environments where
# timely log output is crucial for monitoring and debugging purposes.
#
# Enabling sync can have a performance impact in high-throughput environments.
#
# NOTE: Use STDOUT the immuntable constant here, not $stdout (global var).
#
STDOUT.sync = ENV['STDOUT_SYNC'] && %w[true yes 1].include?(ENV['STDOUT_SYNC'])

# Onetime is the core of the Onetime Secret application.
# It contains the core classes and modules that make up
# the app. It is the main namespace for the application.
#
module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    ERRNO = {}
  end
  @mode = :app

  # d9s: diagnostics is a boolean flag. If true, it will enable Sentry
  module ClassMethods
    attr_accessor :mode, :env, :d9s_enabled
    attr_accessor :i18n_enabled, :supported_locales, :default_locale, :fallback_locale
    attr_reader :conf, :locales, :instance, :sysinfo, :emailer, :global_secret, :global_banner
    attr_writer :debug

    def debug
      @debug ||= ENV['ONETIME_DEBUG'].to_s.match?(/^(true|1)$/i)
    end

    def debug?
      !!debug # force a boolean
    end

    def mode?(guess)
      @mode.to_s == guess.to_s
    end

    def now
      Time.now.utc
    end

    def entropy
      SecureRandom.hex
    end

    # Boot initializes core services and connects models to databases. Must
    # be called after applications are loaded so Familia.members contains
    # all model classes that need database connections.
    #
    # `mode` is a symbol, one of: :app, :cli, :test. It's used for logging
    # but otherwise doesn't do anything special.
    #
    # When `db` is false, the database connections won't be initialized. This
    # is useful for testing or when you want to run code without necessary
    # loading all or any of the models.
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
      exit 1
    rescue Redis::CannotConnectError => e
      OT.le "Cannot connect to redis #{Familia.uri} (#{e.class})"
      exit 10
    rescue StandardError => e
      OT.le "Unexpected error `#{e}` (#{e.class})"
      OT.ld e.backtrace.join("\n")
      exit 99
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

    def le(*msgs)
      msg = msgs.join("#{$/}")
      stderr("E", msg)
    end

    def ld(*msgs)
      return unless Onetime.debug
      msg = msgs.join("#{$/}")
      stderr("D", msg)
    end

    def with_diagnostics(&)
      return unless Onetime.d9s_enabled
      yield # call the block in its own context
    end

    private

    def prepare_emailers
      mail_mode = OT.conf[:emailer][:mode].to_s.to_sym

      mailer_class = case mail_mode
      when :sendgrid
        Onetime::Mail::Mailer::SendGridMailer
      when :ses
        Onetime::Mail::Mailer::SESMailer
      when :smtp
        Onetime::Mail::Mailer::SMTPMailer
      else
        OT.le "Unsupported mail mode: #{mail_mode}, falling back to SMTP"
        Onetime::Mail::Mailer::SMTPMailer
      end

      mailer_class.setup
      @emailer = mailer_class
    end

    def set_global_secret
      @global_secret = OT.conf[:site][:secret] || 'CHANGEME'
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end

    def load_fortunes
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
    end

    def check_global_banner
      @global_banner = Familia.redis(0).get('global_banner')
      OT.li "Global banner: #{OT.global_banner}" if global_banner
    end

    def print_log_banner
      site_config = OT.conf.fetch(:site) # if :site is missing we got real problems
      email_config = OT.conf.fetch(:emailer, {})
      redis_info = Familia.redis.info
      OT.li "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 3}"
      OT.li "system: #{@sysinfo.platform} (ruby #{RUBY_VERSION})"
      OT.li "config: #{OT::Config.path}"
      OT.li "redis: #{redis_info['redis_version']} (#{Familia.uri.serverid})"
      OT.li "familia: v#{Familia::VERSION}"
      OT.li "colonels: #{OT.conf.fetch(:colonels, []).join(', ')}"
      OT.li "i18n: #{OT.i18n_enabled}"
      OT.li "locales: #{@locales.keys.join(', ')}" if OT.i18n_enabled
      OT.li "diagnotics: #{OT.d9s_enabled}"

      if site_config.key?(:authentication)
        OT.li
        OT.li "auth: #{site_config[:authentication].map { |k,v| "#{k}=#{v}" }.join(', ')}"
        OT.li
      end

      if email_config
        mail_settings = {
          mode: email_config[:mode],
          from: "'#{email_config[:fromname]} <#{email_config[:from]}>'",
          host: "#{email_config[:host]}:#{email_config[:port]}",
          region: email_config[:region],
          user: email_config[:user],
          tls: email_config[:tls],
          auth: email_config[:auth] # this is an smtp feature and not credentials
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

    def load_plans
      OT::Plan.load_plans!
    end

    using Familia::HorreumRefinements

    # Connects each model to its configured Redis database.
    #
    # This method retrieves the Redis database configurations from the application
    # settings and establishes connections for each model class within the Familia
    # module. It assigns the appropriate Redis connection to each model and verifies
    # the connection by sending a ping command. Detailed logging is performed at each
    # step to facilitate debugging and monitoring.
    #
    # @example
    #   connect_databases
    #
    # @return [void]
    #
    def connect_databases
      # Connect each model to its configured Redis database
      dbs = OT.conf.dig(:redis, :dbs)

      OT.ld "[connect_databases] dbs: #{dbs}"
      OT.ld "[connect_databases] models: #{Familia.members.map(&:to_s)}"

      # Validate that models have been loaded before attempting to connect
      if Familia.members.empty?
        raise Onetime::Problem, "No known Familia members. Models need to load before calling boot!"
      end

      # Map model classes to their database numbers
      Familia.members.each do |model_class|
        model_sym = model_class.to_sym
        db_index = dbs[model_sym] || DATABASE_IDS[model_sym] || 0 # see models.rb

        # Assign a Redis connection to the model class
        model_class.redis = Familia.redis(db_index)
        ping_result = model_class.redis.ping

        OT.ld "Connected #{model_sym} to DB #{db_index} (#{ping_result})"
      end
    end

    # We always load locales regardless of whether internationalization
    # is enabled. When it's disabled, we just limit the locales to
    # english. Otherwise we would have to text strings to use.
    def load_locales
      i18n = OT.conf.fetch(:internationalization, {})
      OT.i18n_enabled = i18n[:enabled] || false

      OT.ld "Parsing through i18n locales..."

      # Load the locales from the config in both the current and
      # legacy locations. If the locales are not set in the config,
      # we fallback to english.
      locales_list = i18n.fetch(:locales, nil) || OT.conf.fetch(:locales, ['en']).map(&:to_s)

      if OT.i18n_enabled
        # First look for the default locale in the i18n config, then
        # legacy the locales config approach of using the first one.
        OT.supported_locales = locales_list
        OT.default_locale = i18n.fetch(:default_locale, locales_list.first) || 'en'
        OT.fallback_locale = i18n.fetch(:fallback_locale, nil)

        unless locales_list.include?(OT.default_locale)
          OT.le "Default locale #{OT.default_locale} not in locales_list #{locales_list}"
          OT.i18n_enabled = false
        end
      else
        OT.default_locale = 'en'
        OT.supported_locales = [OT.default_locale]
        OT.fallback_locale = nil
      end

      # Iterate over the list of supported locales, to load their JSON
      confs = OT.supported_locales.collect do |loc|
        path = File.join(Onetime::HOME, 'src', 'locales', "#{loc}.json")
        OT.ld "Loading #{loc}: #{File.exist?(path)}"
        begin
          contents = File.read(path)
        rescue Errno::ENOENT => e
          OT.le "Missing locale file: #{path}"
          next
        end
        conf = JSON.parse(contents, symbolize_names: true)
        [loc, conf]
      end

      # Convert the zipped array to a hash
      locales_defs = confs.compact.to_h

      default_locale_def = locales_defs.fetch(OT.default_locale, {})

      # Here we overlay each locale on top of the default just
      # in case there are keys that haven't been translated.
      # That way, at least the default language will display.
      locales_defs.each do |key, locale|
        next if OT.default_locale == key
        locales_defs[key] = OT::Utils.deep_merge(default_locale_def, locale)
      end

      @locales = locales_defs || {}

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
  end

  extend ClassMethods
end

# Sets the SIGINT handler for a graceful shutdown and prevents Sentry from
# trying to send events over the network when we're shutting down via ctrl-c.
trap("SIGINT") do
  OT.li "Shutting down gracefully..."
  begin
    Sentry.close(timeout: 2)  # Attempt graceful shutdown with a short timeout
  rescue StandardError => ex
    # Ignore Sentry errors during shutdown
    OT.le "Error during shutdown: #{ex}"
  end
  exit
end

require_relative 'onetime/mail/choose'
require_relative 'onetime/errors'
require_relative 'onetime/utils'
require_relative 'onetime/version'
require_relative 'onetime/cluster'
require_relative 'onetime/config'
require_relative 'onetime/plan'
require_relative 'onetime/mail'
require_relative 'onetime/alias'
