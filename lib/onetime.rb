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
  
  class Metadata < Storable
    include Familia
    include Gibbler::Complex
    prefix :metadata
    index :key
    field :key
    field :custid
    field :state
    field :secret_key
    field :passphrase
    field :viewed => Integer
    field :shared => Integer
    include Familia::Stamps
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :custid, :secret_key, :entropy
    ttl 7.days
    def initialize custid=nil, entropy=nil
      @custid, @entropy, @state = custid, entropy, :new
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
      exists?
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return if state?(:viewed) || state?(:shared)
      @state = 'viewed'
      @viewed = Time.now.utc.to_i
      save
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def shared!
      @state = 'shared'
      @shared = Time.now.utc.to_i
      @secret_key = nil  # so we don't even know which secret this reffered to.
      save
    end
    def load_secret
      OT::Secret.from_redis secret_key
    end
  end
  
  class Secret < Storable
    include Familia
    include Gibbler::Complex
    prefix :secret
    index :key
    field :key
    field :custid
    field :value
    field :value_checksum
    field :state
    field :original_size
    field :size
    field :passphrase
    field :metadata_key
    field :value_encryption => Integer
    field :passphrase_encryption => Integer
    field :viewed => Integer
    field :shared => Integer
    include Familia::Stamps
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :custid, :passphrase_temp, :value_checksum, :entropy
    ttl 7.days
    def initialize custid=nil, entropy=nil
      @custid, @entropy, @state = custid, entropy, :new
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
      exists? && !value.to_s.empty?
    end
    def encrypt_value v, opts={}
      @value_encryption = 1
      opts.merge! :key => encryption_key 
      @value = v.encrypt opts
      @value_checksum = v.gibbler
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
    def load_metadata
      OT::Metadata.from_redis metadata_key
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
      load_metadata.shared!  # update the private key
      destroy!               # delete this shared key
    end
    def self.generate_pair custid, entropy
      entropy = [entropy, Time.now.to_f * $$].flatten
      metadata, secret = OT::Metadata.new(custid, entropy), OT::Secret.new(custid, entropy)
      metadata.secret_key, secret.metadata_key = secret.key, metadata.key
      [metadata, secret]
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

Onetime::Secret.db 0
Kernel.srand