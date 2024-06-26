# typed: false

require 'bundler/setup'
require 'securerandom'

require 'truemail'

require 'erb'
require 'syslog'

require 'encryptor'
require 'bcrypt'

require 'sendgrid-ruby'

require 'sysinfo'
require 'gibbler/mixins'
require 'familia'
require 'storable'

require_relative 'onetime/core_ext'

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)

Familia.apiversion = nil

# Onetime is the core of the One-Time Secret application.
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

    def mode?(guess)
      @mode.to_s == guess.to_s
    end

    def errno(name)
      name.gibbler.short
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

      @locales = OT.load_locales
      @sysinfo ||= SysInfo.new.freeze
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, $$, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze
      @emailer = Onetime::App::Mail::SMTPMailer

      @emailer.setup

      @global_secret = OT.conf[:site][:secret] || 'CHANGEME'
      Gibbler.secret = global_secret.freeze unless Gibbler.secret && Gibbler.secret.frozen?
      Familia.uri = OT.conf[:redis][:uri]
      OT::RateLimit.register_events OT.conf[:limits]
      OT::ERRNO.freeze unless OT::ERRNO && OT::ERRNO.frozen?
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))

      info "---  ONETIME #{OT.mode} v#{OT::VERSION}  -----------------------------------"
      info "Sysinfo: #{@sysinfo.platform} (#{RUBY_VERSION})"
      info "Config: #{OT::Config.path}"
      ld "Redis:  #{Familia.uri.serverid}" # doesn't print the password
      ld "Limits: #{OT::RateLimit.events}"
      ld "Colonels: #{OT.conf[:colonels]}"
      if OT.conf[:site].key?(:authentication)
        ld "Authentication: #{OT.conf[:site][:authentication]}"
      end

      OT::Plan.load_plans!

      # Make sure we're able to connect to separate Redis databases.
      # Some services like Upstash provide only db 0.
      16.times { |idx|
        uri = Familia.redis.id
        ping_result = Familia.redis(idx).ping
        OT.ld "Connecting to #{uri} (#{ping_result})"
      }

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
      locales
    end

    def to_file(content, filename, mode, chmod = 0o744)
      mode = mode == :append ? 'a' : 'w'
      f = File.open(filename, mode)
      f.puts content
      f.close

      raise OT::Problem("Provided chmod is not an Integer (#{chmod})") unless chmod.is_a?(Integer)

      File.chmod(chmod, filename)
    end

    def info(*msg)
      # prefix = "I(#{Time.now.to_i}):  "
      # msg = "#{prefix}" << msg.join("#{$/}#{prefix}")
      msg = msg.join($/)
      return unless mode?(:app) || mode?(:cli)

      warn(msg) if STDOUT.tty?
      SYSLOG.info msg
    end

    def le(*msg)
      prefix = "E(#{Time.now.to_i}):  "
      msg = "#{prefix}" << msg.join("#{$/}#{prefix}")
      warn(msg) if STDOUT.tty?
      SYSLOG.err msg
    end

    def ld(*msg)
      return unless Onetime.debug

      prefix = "D(#{Time.now.to_i}):  "
      msg = "#{prefix}" << msg.join("#{$/}#{prefix}")
      if STDOUT.tty?
        warn(msg)
      else
        SYSLOG.crit msg
      end
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
