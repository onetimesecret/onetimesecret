# https://github.com/shuber/encryptor
puts "TODO: SECRETS MIGRATION TO REDIS HASH"
puts "TODO: ADD SECRET TO prod config"

require 'bundler/setup'

require 'syslog'

require 'encryptor'
require 'bcrypt'

require 'sysinfo'
require 'gibbler'
require 'familia'
require 'storable'

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)
Familia.apiversion = nil

module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    ERRNO = {
      :internalerror.gibbler.short => 'Not found',
      :nosecret.gibbler.short => 'No secret provided',
    }.freeze unless defined?(Onetime::ERRNO)
  end
  @debug = false
  @mode = :app
  class << self
    attr_accessor :debug, :mode
    attr_reader :conf, :instance, :sysinfo
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
      @sysinfo = SysInfo.new.freeze
      @instance = [OT.sysinfo.hostname, OT.sysinfo.user, $$, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze
      secret = OT.conf[:site][:secret] || "CHANGEME"
      Gibbler.secret = secret.freeze
      Familia.uri = OT.conf[:redis][:uri]
      OT::RateLimit.register_events OT.conf[:limits]
      info "---  ONETIME v#{OT::VERSION}  -----------------------------------"
      info "Config: #{OT::Config.path}"
      info " Redis: #{Familia.uri}"
      info "Secret: #{secret}"
      info "Limits: #{OT::RateLimit.events}"
      @conf
    end
    def sysinfo
      @sysinfo = SysInfo.new.freeze if @sysinfo.nil?
      @sysinfo
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
  module Entropy
    @values = Familia::Set.new name.to_s.downcase.gsub('::', Familia.delim).to_sym
    class << self
      attr_reader :values
      def pop
        OT.info "TODO: OT::Entropy.pop"
        values.pop ||
        [caller[0], rand].gibbler.shorten(12) # TODO: replace this stub
      end
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
    def strand(len=12, safe=true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size-1)] }.join
    end
  end
  
  class Problem < RuntimeError
  end
  class MissingSecret < Problem
  end
  class UnknownKind < Problem
  end
  class LimitExceeded < RuntimeError
  end
end
OT = Onetime

require 'onetime/models'
require 'onetime/logic'

Kernel.srand


