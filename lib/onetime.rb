# https://github.com/shuber/encryptor

require 'bundler/setup'

require 'syslog'
SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)

require 'encryptor'
require 'bcrypt'

require 'gibbler'
Gibbler.secret = "(I AM THE ONE TRUE SECRET!)"

require 'familia'
require 'storable'

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
    attr_accessor :debug
    attr_reader :conf
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
  
  class MissingSecret < RuntimeError
  end
  
  class Secret < Storable
    include Familia
    include Gibbler::Complex
    index :key
    field :kind
    field :key
    field :value
    field :state
    field :original_size
    field :size
    field :passphrase
    field :paired_key
    field :custid
    field :value_encryption => Integer
    field :passphrase_encryption => Integer
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :kind, :entropy
    field :viewed => Integer
    field :shared => Integer
    include Familia::Stamps
    ttl 7.days
    def initialize kind=nil, entropy=nil
      unless kind.nil? || [:private, :shared].member?(kind.to_s.to_sym)
        raise ArgumentError, "Bad kind: #{kind}"
      end
      @state, @value_encryption, @passphrase_encryption = :new, 0, 0
      @kind, @entropy = kind, entropy
    end
    def customer?
      ! custid.nil?
    end
    def size
      value.to_s.size
    end
    def long
      original_size >= 5000
    end
    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end
    def older_than? seconds
      age > seconds
    end
    def key
      @key ||= gibbler.base(36)
      @key
    end
    def valid?
      case kind.to_s
      when 'shared'
        exists? && !value.to_s.empty?
      when 'private'
        exists?
      else
        false
      end
    end
    def encrypt_value v, opts={}
      @value_encryption = 1
      opts.merge! :key => encryption_key 
      @value = v.encrypt opts
    end
    def can_decrypt?
      passphrase.to_s.empty? || !passphrase_temp.to_s.empty?
    end
    def decrypted_value opts={}
      case value_encryption.to_i
      when 0
        self.value
      when 1
        opts.merge! :key => encryption_key
        self.value.decrypt opts
      else
        raise RuntimeError, "Unknown encryption"
      end
    end
    def encryption_key
      OT::Secret.encryption_key self.key, self.passphrase_temp
    end
    def update_passphrase v
      @passphrase_encryption = 1
      @passphrase_temp = v
      @passphrase = BCrypt::Password.create(v, :cost => 10).to_s
    end
    def has_passphrase?
      !passphrase.to_s.empty?
    end
    def passphrase? guess
      begin 
        ret = !has_passphrase? || BCrypt::Password.new(@passphrase) == guess
        @passphrase_temp = guess if ret  # used to decrypt the value
        ret
      rescue BCrypt::Errors::InvalidHash => ex
        msg = "[old-passphrase]"
        !has_passphrase? || (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end
    def load_pair
      self.class.from_redis paired_key
    end
    def kind? guess
      kind.to_s == guess.to_s
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def shared!
      @state = 'shared'
      @shared = Time.now.utc.to_i
      save
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return if state?(:viewed) || state?(:shared)
      @state = 'viewed'
      @viewed = Time.now.utc.to_i
      if kind?(:shared)
        load_pair.shared!  # update the private key
        destroy!           # delete this shared key
      else
        save
      end
    end
    def self.generate_pair entropy
      entropy = [entropy, Time.now.to_f * $$].flatten
      psecret, ssecret = new(:private, entropy), new(:shared, entropy)
      psecret.paired_key, ssecret.paired_key = ssecret.key, psecret.key
      [psecret, ssecret]
    end
    def self.encryption_key *entropy
      #entropy.unshift Gibbler.secret     # If we change this the values are fucked.
      Digest::SHA256.hexdigest(entropy.flatten.compact.join(':'))   # So don't use gibbler here either.
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