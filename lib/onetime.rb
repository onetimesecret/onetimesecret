
# rubocop:disable Metrics/ModuleLength
# https://github.com/shuber/encryptor

require 'bundler/setup'

require 'onetime/core_ext'

require 'erb'
require 'syslog'

require 'encryptor'
require 'bcrypt'

require 'sysinfo'
require 'gibbler'
require 'familia'
require 'storable'
require 'sendgrid-ruby'

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)
Familia.apiversion = nil

module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    ERRNO = {}
  end
  @mode = :app
  class << self
    attr_accessor :mode
    attr_reader :conf, :locales, :instance, :sysinfo, :emailer, :global_secret
    attr_writer :debug

    def debug
      @debug || (@debug.nil? && ENV['ONETIME_DEBUG'].to_s == 'true' || ENV['ONETIME_DEBUG'].to_i == 1)
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

    def load!(mode = nil, _base = Onetime::HOME)
      OT.mode = mode unless mode.nil?
      @conf = OT::Config.load # load config before anything else.
      @locales = OT.load_locales
      @sysinfo ||= SysInfo.new.freeze
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, $$, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze
      OT::SMTP.setup
      @global_secret = OT.conf[:site][:secret] || 'CHANGEME'
      Gibbler.secret = global_secret.freeze unless Gibbler.secret && Gibbler.secret.frozen?
      Familia.uri = OT.conf[:redis][:uri]
      OT::RateLimit.register_events OT.conf[:limits]
      OT::ERRNO.freeze unless OT::ERRNO && OT::ERRNO.frozen?
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
      ld "---  ONETIME #{OT.mode} v#{OT::VERSION}  -----------------------------------"
      ld "Config: #{OT::Config.path}"
      # ld "Redis:  #{Familia.uri.serverid}" # don't print the password
      ld "Limits: #{OT::RateLimit.events}"
      OT::Plan.load_plans!
      # Digest lazy-loads classes. We need to make sure these
      # are loaded so we can increase the $SAFE level.
      Digest::SHA256
      Digest::SHA384
      Digest::SHA512
      # Seed the random number generator
      Kernel.srand
      # Need to connect to all redis DBs so we can increase $SAFE level.
      begin
        16.times { |idx| OT.ld format('Connecting to %s (%s)', Familia.redis(idx).uri, Familia.redis(idx).ping) }
        OT::SplitTest.from_config OT.conf[:split_tests]
        if OT::Entropy.count < 5_000
          info "Entropy is low (#{OT::Entropy.count}). Generating..."
          OT::Entropy.generate
        end
      rescue StandardError => e
        raise e unless mode?(:cli)

        OT.info "Cannot connect to redis #{Familia.uri}"
      end
      @conf
    end

    def load_locales(locales = OT.conf[:locales] || ['en'])
      confs = locales.collect do |locale|
        OT.ld 'Loading locale: %s' % locale
        conf = OT::Config.load format('%s/locale/%s', OT::Config.dirname, locale)
        [locale, conf]
      end
      locales = Hash[confs] # convert zipped array to hash
      default_locale = locales[OT.conf[:locales].first] # default locale is the first
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
      raise "Provided chmod is not a Fixnum (#{chmod})" unless chmod.is_a?(Integer)

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
  module Config
    extend self
    SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
    UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
    attr_reader :env, :base, :bootstrap

    def load(path = self.path)
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)

      YAML.load(ERB.new(File.read(path)).result)
    rescue StandardError => e
      SYSLOG.err e.message
      msg = if path =~ /locale/
              "Error loading locale: #{path} (#{e.message})"
            else
              "Error loading config: #{path}"
            end
      Onetime.info msg
      Kernel.exit(1)
    end

    def exists?
      !config_path.nil?
    end

    def dirname
      @dirname ||= File.dirname(path)
    end

    def path
      @path ||= find_configs.first
    end

    def find_configs
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |f|
        f = File.join File.expand_path(f), 'config'
        Onetime.ld "Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end
  end

  module VERSION
    def self.to_a
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH], @version[:BUILD]]
    end

    def self.to_s
      to_a[0..-2].join('.')
    end

    def self.inspect
      to_a.join('.')
    end

    def self.increment!(msg = nil)
      load_config
      @version[:BUILD] = (@version[:BUILD] || '000').to_s.succ!.to_s
      @version[:STAMP] = Time.now.utc.to_i
      @version[:OWNER] = OT.sysinfo.user
      @version[:STORY] = msg || '[no message]'
      OT.to_file @version.to_yaml, File.join(OT::HOME, 'BUILD.yml'), 'w'
      @version
    end

    def self.load_config
      return if @version

      require 'yaml'
      @version = YAML.load_file(File.join(OT::HOME, 'BUILD.yml'))
    end
  end

  module Utils
    extend self
    unless defined?(VALID_CHARS)
      VALID_CHARS = [('a'..'z').to_a, ('A'..'Z').to_a, ('0'..'9').to_a, %w[* $ ! ? ( )]].flatten
      VALID_CHARS_SAFE = VALID_CHARS.clone
      VALID_CHARS_SAFE.delete_if { |v| %w[i l o 1 0].member?(v) }
      VALID_CHARS.freeze
      VALID_CHARS_SAFE.freeze
    end
    attr_accessor :fortunes

    def self.random_fortune
      @fortunes.random.to_s.strip
    rescue StandardError
      'A house is full of games and puzzles.'
    end

    def strand(len = 12, safe = true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size - 1)] }.join
    end

    def indifferent_params(params)
      if params.is_a?(Hash)
        params = indifferent_hash.merge(params)
        params.each do |key, value|
          next unless value.is_a?(Hash) || value.is_a?(Array)

          params[key] = indifferent_params(value)
        end
      elsif params.is_a?(Array)
        params.collect! do |value|
          if value.is_a?(Hash) || value.is_a?(Array)
            indifferent_params(value)
          else
            value
          end
        end
      end
    end

    # Creates a Hash with indifferent access.
    def indifferent_hash
      Hash.new { |hash, key| hash[key.to_s] if key.is_a?(Symbol) }
    end

    def deep_merge(default, overlay)
      merger = proc { |_key, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.merge(v2, &merger) : v2 }
      default.merge(overlay, &merger)
    end

    def obscure_email(text)
      regex = /(\b(([A-Z0-9]{1,2})[A-Z0-9._%-]*)([A-Z0-9])?(@([A-Z0-9])[A-Z0-9.-]+(\.[A-Z]{2,4}\b)))/i
      el = text.split('@')
      text.gsub regex, '\\3*****\\4@\\6*****\\7'
    end
  end

  class Plan
    class << self
      attr_reader :plans

      def add_plan planid, *args
        @plans ||= {}
        new_plan = new planid, *args
        plans[new_plan.planid] = new_plan
        plans[new_plan.planid.gibbler.short] = new_plan
      end

      def normalize(planid)
        planid.to_s.downcase
      end

      def plan(planid)
        plans[normalize(planid)]
      end

      def plan?(planid)
        plans.member?(normalize(planid))
      end

      def load_plans!
        add_plan :anonymous, 0, 0, ttl: 7.days, size: 1_000_000, api: false, name: 'Anonymous'
        add_plan :personal_v1, 5.0, 1, ttl: 14.days, size: 1_000_000, api: false, name: 'Personal'
        add_plan :personal_v2, 10.0, 0.5, ttl: 30.days, size: 1_000_000, api: true, name: 'Personal'
        add_plan :personal_v3, 5.0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Personal'
        add_plan :professional_v1, 30.0, 0.50, ttl: 30.days, size: 1_000_000, api: true, cname: true,
                                               name: 'Professional'
        add_plan :professional_v2, 30.0, 0.333333, ttl: 30.days, size: 1_000_000, api: true, cname: true,
                                                   name: 'Professional'
        add_plan :agency_v1, 100.0, 0.25, ttl: 30.days, size: 1_000_000, api: true, private: true,
                                          name: 'Agency'
        add_plan :agency_v2, 75.0, 0.33333333, ttl: 30.days, size: 1_000_000, api: true, private: true,
                                               name: 'Agency'
        # Hacker News special
        add_plan :personal_hn, 0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'HN Special'
        # Reddit special
        add_plan :personal_reddit, 0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Reddit Special'
        # Added 2011-12-24s
        add_plan :basic_v1, 10.0, 0.5, ttl: 30.days, size: 1_000_000, api: true, name: 'Basic'
        add_plan :individual_v1, 0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Individual'
        # Added 2012-01-27
        add_plan :nonprofit_v1, 0, 0, ttl: 30.days, size: 1_000_000, api: true, cname: true,
                                      name: 'Non Profit'
      end
    end
    attr_reader :planid, :price, :discount, :options

    def initialize(planid, price, discount, options = {})
      @planid = self.class.normalize(planid)
      @price = price
      @discount = discount
      @options = options
    end

    def calculated_price
      (price * (1 - discount)).to_i
    end

    def paid?
      !free?
    end

    def free?
      calculated_price.zero?
    end
  end

  class Problem < RuntimeError
  end

  class MissingSecret < Problem
  end

  class UnknownKind < Problem
  end

  class FormError < Problem
    attr_accessor :form_fields, :message
  end

  class BadShrimp < Problem
    attr_reader :path, :user, :got, :wanted

    def initialize(path, user, got, wanted)
      @path = path
      @user = user
      @got = got.to_s
      @wanted = wanted.to_s
    end

    def report
      "BAD SHRIMP FOR #{@path}: #{@user}: #{got.shorten(16)}/#{wanted.shorten(16)}"
    end

    def message
      'Sorry, bad shrimp'
    end
  end

  class LimitExceeded < RuntimeError
    attr_accessor :event, :message, :cust
    attr_reader :identifier, :event, :count

    def initialize(identifier, event, count)
      @identifier = identifier
      @event = event
      @count = count
    end
  end
end
OT = Onetime

require 'onetime/models'
require 'onetime/logic'
require 'onetime/email'
