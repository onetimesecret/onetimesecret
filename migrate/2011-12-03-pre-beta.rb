# ruby -Ilib migrate/2011-12-03-pre-beta.rb

require 'onetime'
require 'familia/tools'


if true #ARGV.first != 'MIGRATE'
  OT.info "No change made (already migrated 2011-12-03)"
  exit 
end

def run
  OT.load! :app
  
  secrets = Familia.redis(0).keys 'secret:*:object'; nil
  OT.info "Migrating #{secrets.size} secrets"
  secrets.collect! { |key|
    obj = OldModel::Secret.from_key(key)
    s = OT::Secret.new
    s.key = obj.key
    s.update_fields obj.to_hash
  }; nil
  
  metadata = Familia.redis(0).keys 'metadata:*:object'; nil
  OT.info "Migrating #{metadata.size} metadata"
  metadata.collect! { |key|
    obj = OldModel::Metadata.from_key(key)
    s = OT::Metadata.new
    s.key = obj.key
    s.update_fields obj.to_hash
  }; nil
  
end

module OldModel
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
    db 0
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
    db 0
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
    def self.spawn_pair custid, entropy
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
end


begin 
  run
rescue => ex
  puts "#{ex.class} #{ex.message}", ex.backtrace
  exit 1
end
