
require 'syslog'
SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)

require 'gibbler'
Gibbler.secret = "(I AM THE ONE TRUE SECRET!)"

require 'familia'
require 'storable'

module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..') )
  end
  @debug = false
  class << self
    attr_accessor :debug
    attr_reader :conf
    def load! env=:dev, base=Onetime::HOME
      env && @env = env.to_sym.freeze
      conf_path = File.join(base, 'etc', env.to_s, 'onetime.yml')
      ld "Loading #{conf_path}"
      @conf = read_config(conf_path)
      Familia.uri = Onetime.conf[:site][:redis][:uri]
      info "---  ONETIME ALPHA  -----------------------------------"
      info "Connection: #{Familia.uri}"
      @conf
    end
    
    def read_config path
      raise ArgumentError, "Bad config: #{path}" unless File.extname(path) == '.yml'
      raise ArgumentError, "Bad config: #{path}" unless File.owned?(path)
      YAML.load_file path
    end
    
    def info(*msg)
      prefix = "(#{Time.now}):  "
      STDERR.puts "#{prefix}" << msg.join("#{$/}#{prefix}")
      STDERR.flush
    end

    def ld(*msg)
      return unless Onetime.debug
      prefix = "D:  "
      STDERR.puts "#{prefix}" << msg.join("#{$/}#{prefix}")
      STDERR.flush
    end
  end
  
  class Secret < Storable
    include Familia
    include Gibbler::Complex
    index :key
    field :kind
    field :key
    field :value
    field :state
    field :paired_key
    attr_reader :entropy
    gibbler :kind, :entropy
    include Familia::Stamps
    def initialize kind=nil, entropy=nil
      unless kind.nil? || [:private, :shared].member?(kind.to_s.to_sym)
        raise ArgumentError, "Bad kind: #{kind}"
      end
      @state = :new
      @kind, @entropy = kind, entropy
    end
    def key
      @key ||= gibbler.base(36)
      @key
    end
    def load_pair
      ret = self.class.from_redis paired_key
      ret
    end
    def self.generate_pair entropy
      entropy = [entropy, Time.now.to_f * $$].flatten
      psecret, ssecret = new(:private, entropy), new(:shared, entropy)
      psecret.paired_key, ssecret.paired_key = ssecret.key, psecret.key
      [psecret, ssecret]
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

end
OT = Onetime

Onetime::Secret.db 0
Kernel.srand