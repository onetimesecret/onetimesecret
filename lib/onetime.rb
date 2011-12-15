# https://github.com/shuber/encryptor

require 'bundler/setup'

require 'onetime/core_ext'

require 'syslog'

require 'encryptor'
require 'bcrypt'

require 'sysinfo'
require 'gibbler'
require 'familia'
require 'storable'
require 'thirdparty/sendgrid'

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)
Familia.apiversion = nil

module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    ERRNO = {
    } unless defined?(Onetime::ERRNO)
  end
  @debug = false
  @mode = :app
  class << self
    attr_accessor :debug, :mode
    attr_reader :conf, :instance, :sysinfo, :emailer
    def mode? guess
      @mode.to_s == guess.to_s
    end
    def errno name
      name.gibbler.short
    end
    def now
      Time.now.utc
    end
    def entropy
      OT::Entropy.pop
    end
    def load! mode=nil, base=Onetime::HOME
      OT.mode = mode unless mode.nil?
      @conf = OT::Config.load  # load config before anything else.
      @sysinfo ||= SysInfo.new.freeze
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, $$, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze
      emailer_opts = OT.conf[:emailer].values_at :account, :password, :from, :fromname, :bcc
      @emailer = SendGrid.new *emailer_opts
      secret = OT.conf[:site][:secret] || "CHANGEME"
      Gibbler.secret = secret.freeze unless Gibbler.secret && Gibbler.secret.frozen?
      Familia.uri = OT.conf[:redis][:uri]
      OT::RateLimit.register_events OT.conf[:limits]
      OT::ERRNO.freeze unless OT::ERRNO && OT::ERRNO.frozen?
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
      OT::SplitTest.from_config OT.conf[:split_tests] 
      info "---  ONETIME v#{OT::VERSION}  -----------------------------------"
      info "Config: #{OT::Config.path}"
      info " Redis: #{Familia.uri}"
      info "Secret: #{secret}"
      info "Limits: #{OT::RateLimit.events}"
      if OT::Entropy.count < 10_000
        info "Entropy is low (#{OT::Entropy.count}). Generating..."
        OT::Entropy.generate
      end
      info "Entropy: #{OT::Entropy.count}"
      # Digest lazy-loads classes. We need to make sure these
      # are loaded so we can increase the $SAFE level.
      Digest::SHA256
      Digest::SHA384
      Digest::SHA512
      # Seed the random number generator
      Kernel.srand
      # Need to connect to all redis DBs so we can increase $SAFE level.
      16.times { |idx| OT.info 'Connecting to %s (%s)' % [Familia.redis(idx).uri, Familia.redis(idx).ping] }
      @conf
    end
    def to_file(content, filename, mode, chmod=0744)
      mode = (mode == :append) ? 'a' : 'w'
      f = File.open(filename,mode)
      f.puts content
      f.close
      raise "Provided chmod is not a Fixnum (#{chmod})" unless chmod.is_a?(Fixnum)
      File.chmod(chmod, filename)
    end
    def info(*msg)
      prefix = "I(#{Time.now.to_i}):  "
      msg = "#{prefix}" << msg.join("#{$/}#{prefix}")
      STDERR.puts(msg) if STDOUT.tty?
      SYSLOG.info msg
    end
    def ld(*msg)
      return unless Onetime.debug
      prefix = "D(#{Time.now.to_i}):  "
      msg = "#{prefix}" << msg.join("#{$/}#{prefix}")
      STDERR.puts(msg) if STDOUT.tty?
      SYSLOG.crit msg
    end
  end
  module Config
    extend self
    SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
    UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
    attr_reader :env, :base, :bootstrap
    def load path=self.path
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)
      YAML.load_file path
    end
    def exists?
      !config_path.nil?
    end
    def path
      find_configs.first
    end
    def find_configs
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect { |f| 
        f = File.join File.expand_path(f), 'config'
        Onetime.ld "Looking for #{f}"
        f if File.exists?(f) 
      }.compact
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
    def self.increment!(msg=nil)
      load_config
      @version[:BUILD] = @version[:BUILD].to_s.succ!
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
      VALID_CHARS = [("a".."z").to_a, ("A".."Z").to_a, ("0".."9").to_a, %w[* $ ! ? ( )]].flatten
      VALID_CHARS_SAFE = VALID_CHARS.clone
      VALID_CHARS_SAFE.delete_if { |v| %w(i l o 1 0).member?(v) }
      VALID_CHARS.freeze
      VALID_CHARS_SAFE.freeze
    end
    attr_accessor :fortunes
    def self.random_fortune
      @fortunes.random.to_s.strip
    rescue => ex
      'A house is full of games and puzzles.'
    end
    def strand(len=12, safe=true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size-1)] }.join
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
      Hash.new {|hash,key| hash[key.to_s] if Symbol === key }
    end
  end
  
  class Plan
    class << self
      attr_reader :plans
      def add_plan planid, *args
        @plans ||= Onetime::Utils.indifferent_hash
        plans[planid.to_s] = new planid, *args
      end
      def plan? planid
        @plans.member?(planid.to_s)
      end
    end
    attr_reader :planid, :price, :discount, :options
    def initialize planid, price, discount, options={}
      @planid, @price, @discount, @options = planid, price, discount, options
    end
    def calculated_price
      (price * (1-discount)).to_i
    end
    add_plan :anonymous, 0, 0, :ttl => 2.days, :size => 1_000, :api => false, :name => 'Anonymous'
    add_plan :personal_v1, 5.0, 1, :ttl => 14.days, :size => 1_000, :api => false, :name => 'Personal'
    add_plan :personal_v2, 10.0, 0.5, :ttl => 30.days, :size => 1_000, :api => true, :name => 'Personal'
    add_plan :personal_v3, 5.0, 0, :ttl => 14.days, :size => 1_000, :api => true, :name => 'Personal'
    add_plan :professional_v1, 30.0, 0.50, :ttl => 90.days, :size => 5_000, :api => true, :cname => true, :name => 'Professional'
    add_plan :professional_v2, 30.0, 0.333333, :ttl => 90.days, :size => 5_000, :api => true, :cname => true, :name => 'Professional'
    add_plan :agency_v1, 100.0, 0.25, :ttl => 90.days, :size => 10_000, :api => true, :private => true, :name => 'Agency'
    add_plan :agency_v2, 75.0, 0.33333333, :ttl => 90.days, :size => 10_000, :api => true, :private => true, :name => 'Agency'
    # Hacker News special
    add_plan :personal_hn, 10.0, 1, :ttl => 14.days, :size => 1_000, :api => true, :name => 'Personal (HN)'
    # Reddit special
    add_plan :personal_reddit, 10.0, 1, :ttl => 14.days, :size => 1_000, :api => true, :name => 'Reddit Special'
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
    def initialize path, user, got, wanted
      @path, @user, @got, @wanted = path, user, got.to_s, wanted.to_s
    end
    def report()
      "BAD SHRIMP FOR #{@path}: #{@user}: #{got.shorten(16)}/#{wanted.shorten(16)}"
    end
    def message() 
      "Sorry, bad shrimp"
    end
  end
  class LimitExceeded < RuntimeError
    attr_accessor :event, :message, :cust
    attr_reader :identifier, :event, :count
    def initialize identifier, event, count
      @identifier, @event, @count = identifier, event, count
    end
  end
end
OT = Onetime

require 'onetime/models'
require 'onetime/logic'
require 'onetime/email'


