
module Onetime
  class Secret < Familia::HashKey
    include Onetime::Models::RedisHash
    include Gibbler::Complex
    #prefix :secret
    #index :key
    #field :key
    #field :custid
    #field :value
    #field :value_checksum
    #field :state
    #field :original_size
    #field :size
    #field :passphrase
    #field :metadata_key
    #field :value_encryption => Integer
    #field :passphrase_encryption => Integer
    #field :viewed => Integer
    #field :shared => Integer
    #include Familia::Stamps
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :custid, :passphrase_temp, :value_checksum, :entropy
    db 2
    def initialize custid=nil, entropy=nil
      @custid, @entropy, @state = custid, entropy, :new
      @key = gibbler.base(36)
      super name, :ttl => 7.days, :db => 2
    end
    def update_fields hsh={}
      hsh[:custid] ||= custid
      super hsh
    end
    def identifier
      @key
    end
    def key= objid
      @key = objid
      @name = name
      @key
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
      @age ||= Time.now.utc.to_i-self.updated
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
      self.value_encryption = 1
      opts.merge! :key => encryption_key 
      self.value = v.encrypt opts
      self.value_checksum = v.gibbler
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
      self.passphrase_encryption = 1
      @passphrase_temp = v
      self.passphrase = BCrypt::Password.create(v, :cost => 10).to_s
    end
    def has_passphrase?
      !passphrase.to_s.empty?
    end
    def passphrase? guess
      begin 
        ret = !has_passphrase? || BCrypt::Password.new(passphrase) == guess
        @passphrase_temp = guess if ret  # used to decrypt the value
        ret
      rescue BCrypt::Errors::InvalidHash => ex
        msg = "[old-passphrase]"
        !has_passphrase? || (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end
    def load_metadata
      OT::Metadata.load metadata_key
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def shared!
      update_fields :state => :shared, :shared => Time.now.utc.to_i, :secret_key => nil
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return if state?(:viewed) || state?(:shared)
      update_fields :state => :viewed, :viewed => Time.now.utc.to_i
      load_metadata.shared!  # update the private key
      destroy!               # delete this shared key
    end
    class << self
      def exists? objid
        obj = new 
        obj.key = objid
        obj.exists?
      end
      def load objid
        obj = new 
        obj.key = objid
        obj.exists? ? obj : nil
      end
      def create custid, entropy=[]
        obj = new custid, entropy << [OT.instance, Time.now.to_f, OT.entropy]
        # force the storing of the fields to redis
        obj.update_fields :custid => custid # calls update_time!
        obj
      end
      def generate_pair custid, entropy
        entropy = [OT.instance, Time.now.to_f, entropy].flatten
        metadata, secret = OT::Metadata.new(custid, entropy), OT::Secret.new(custid, entropy)
        metadata.secret_key, secret.metadata_key = secret.key, metadata.key
        [metadata, secret]
      end
      def encryption_key *entropy
        #entropy.unshift Gibbler.secret     # If we change this the values are fucked.
        Digest::SHA256.hexdigest(entropy.flatten.compact.join(':'))   # So don't use gibbler here either.
      end
    end
  end
end