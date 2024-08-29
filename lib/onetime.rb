# typed: false

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

  module ClassMethods
    attr_accessor :mode
    attr_reader :conf, :locales, :instance, :sysinfo, :emailer, :global_secret
    attr_writer :debug

    def debug
      @debug || ((@debug.nil? && ENV['ONETIME_DEBUG'].to_s == 'true') || ENV['ONETIME_DEBUG'].to_i == 1)
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

    def boot!(mode = nil)
      OT.mode = mode unless mode.nil?
      @conf = OT::Config.load # load config before anything else.
      OT::Config.after_load(@conf)

      Familia.uri = OT.conf[:redis][:uri]
      @sysinfo ||= SysInfo.new.freeze
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, $$, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze

      load_locales
      set_global_secret
      prepare_emailers
      prepare_rate_limits
      load_fortunes
      load_plans
      connect_databases
      print_banner

      @conf # return the config

    rescue OT::Problem => e
      OT.le "Problem booting: #{e.message}"
      exit 1
    rescue Redis::CannotConnectError => e
      OT.le "Cannot connect to redis #{Familia.uri} (#{e.class})"
      exit 10
    rescue StandardError => e
      OT.le "Unexpected error `#{e}` (#{e.class})"
      exit 99
    end

    def info(*msgs)
      return unless mode?(:app) || mode?(:cli) # can reduce output in tryouts
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

    private

    def prepare_emailers
      @emailer = Onetime::App::Mail::SMTPMailer
      @emailer.setup
    end

    def set_global_secret
      @global_secret = OT.conf[:site][:secret] || 'CHANGEME'
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end

    def prepare_rate_limits
      OT::RateLimit.register_events OT.conf[:limits]
    end

    def load_fortunes
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
    end

    def print_banner
      redis_info = Familia.redis.info
      info "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 10}"
      info "Sysinfo: #{@sysinfo.platform} (#{RUBY_VERSION})"
      info "Config: #{OT::Config.path}"
      info "Redis (#{redis_info['redis_version']}): #{Familia.uri.serverid}" # servid doesn't print the password
      info "Familia: #{Familia::VERSION}"
      info "Colonels: #{OT.conf[:colonels]}"
      if OT.conf[:site].key?(:authentication)
        info "Authentication: #{OT.conf[:site][:authentication]}"
      end
      if OT.conf[:site].key?(:domains)
        info "Domains: #{OT.conf[:site][:domains]}"
      end
      if OT.conf[:development][:enabled]
        info "Frontend: #{OT.conf[:development][:frontend_host]}"
      end
      info "Loaded locales: #{@locales.keys.join(', ')}"
      info "Limits: #{OT::RateLimit.events}"
    end

    def load_plans
      OT::Plan.load_plans!
    end

    def connect_databases
      # Make sure we're able to connect to separate Redis databases. Some
      # services provide only db 0 and this is a good way to check early.
      16.times { |idx|
        uri = Familia.redis.id
        ping_result = Familia.redis(idx).ping
        OT.ld "Connecting to #{uri} (#{ping_result})"
      }
    end

    def load_locales(locales = OT.conf[:locales] || ['en'])
      confs = locales.collect do |locale|
        path = File.join(OT::Config.dirname, 'locale', locale)
        OT.ld "Loading locale #{locale}: #{File.exist?(path)}"
        conf = OT::Config.load(path)
        [locale, conf]
      end

      # Convert the zipped array to a hash
      locales = confs.to_h
      # Make sure the default locale is first
      default_locale = locales[OT.conf[:locales].first]
      # Here we overlay each locale on top of the default just
      # in case there are keys that haven't been translated.
      # That way, at least the default language will display.
      locales.each do |key, locale|
        locales[key] = OT::Utils.deep_merge(default_locale, locale) if default_locale != locale
      end
      @locales = locales
    end

    def stdout(prefix, msg)
      stamp = Time.now.to_i
      logline = "%s(%s): %s" % [prefix, stamp, msg]
      STDOUT.puts(logline)
    end

    def stderr(prefix, msg)
      stamp = Time.now.to_i
      logline = "%s(%s): %s" % [prefix, stamp, msg]
      STDERR.puts(logline)
    end
  end

  extend ClassMethods
end

require_relative 'onetime/errors'
require_relative 'onetime/utils'
require_relative 'onetime/version'
require_relative 'onetime/config'
require_relative 'onetime/plan'
require_relative 'onetime/alias'
require_relative 'onetime/models'
require_relative 'onetime/logic'
require_relative 'onetime/app'
