# https://github.com/shuber/encryptor

require 'bundler/setup'

require 'syslog'

require 'encryptor'
require 'bcrypt'

require 'gibbler'
require 'familia'
require 'storable'

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)
Gibbler.secret = "(I AM THE ONE TRUE SECRET!)".freeze
Familia.secret = "[WHAT IS UP MY FAMILIALS??]".freeze


module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    ERRNO = {
      :internalerror.gibbler.short => 'Not found',
      :nosecret.gibbler.short => 'No secret provided',
    }.freeze unless defined?(Onetime::ERRNO)
  end
  @debug = false
  class << self
    attr_accessor :debug, :mode
    attr_reader :conf
    def mode? guess
      @mode.to_s == guess.to_s
    end
    def errno name
      name.gibbler.short
    end
    def load! env=:dev, base=Onetime::HOME
      env && @env = env.to_sym.freeze
      conf_path = File.join(base, 'etc', env.to_s, 'onetime.yml')
      info "Loading #{conf_path}"
      @conf = read_config(conf_path)
      Familia.uri = Onetime.conf[:site][:redis][:uri]
      info "---  ONETIME ALPHA  -----------------------------------"
      info "Connection: #{Familia.uri}"
      @conf
    end
    
    def read_config path
      raise ArgumentError, "Bad config: #{path}" unless File.extname(path) == '.yml'
      raise RuntimeError, "Bad config: #{path}" unless File.exists?(path)
      YAML.load_file path
    end
    
    def info(*msg)
      prefix = "(#{Time.now}):  "
      SYSLOG.info "#{prefix}" << msg.join("#{$/}#{prefix}")
    end

    def ld(*msg)
      return unless Onetime.debug
      prefix = "D:  "
      SYSINFO.crit "#{prefix}" << msg.join("#{$/}#{prefix}")
    end
  end
  
  class MissingSecret < RuntimeError
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
    def self.load_config
      return if @version
      require 'yaml'
      @version = YAML.load_file(File.join(OT::HOME, 'BUILD.yml'))
    end
  end
end
OT = Onetime

require 'onetime/models'

Onetime::Secret.db 0
Kernel.srand