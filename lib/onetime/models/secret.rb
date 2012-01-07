
module Onetime
  class Secret < Familia::HashKey
    include Onetime::Models::RedisHash
    include Onetime::Models::Passphrase
    include Gibbler::Complex
    attr_reader :entropy
    gibbler :custid, :passphrase_temp, :entropy
    def initialize custid=nil, entropy=nil
      @custid, @entropy, @state = custid, entropy, :new
      @key = gibbler.base(36)
      super name, :db => 8, :ttl => 7.days
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
    def value_length
      value.to_s.size
    end
    def long
      original_size >= 5000
    end
    def maxviews
      (get_value(:maxviews) || 1).to_i
    end
    def view_count
      (get_value(:view_count) || 0).to_i
    end
    def maxviews?
      self.view_count >= self.maxviews
    end
    def viewable?
      has_key?(:value) && (state?(:new) || !maxviews?)
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
    def truncated
      self.original_size.to_i >= 4999
    end
    def encrypt_value original_value, opts={}
      storable_value = original_value.slice(0, 4999)
      self.original_size = original_value.size
      self.value_checksum = storable_value.gibbler
      self.value_encryption = 2
      self.value = storable_value.encrypt opts.merge(:key => encryption_key)
    end
    def decrypted_value opts={}
      case value_encryption.to_i
      when 0
        self.value
      when 1
        self.value.decrypt opts.merge(:key => encryption_key_v1)
      when 2
        self.value.decrypt opts.merge(:key => encryption_key_v2)
      else
        raise RuntimeError, "Unknown encryption mode: #{value_encryption}"
      end
    end
    def can_decrypt?
      !value.to_s.empty?  && (passphrase.to_s.empty? || !passphrase_temp.to_s.empty?)
    end
    def encryption_key *args
      case value_encryption.to_i
      when 0
        self.value
      when 1  # Last used 2012-01-07
        encryption_key_v1 *args
      when 2
        encryption_key_v2 *args
      else
        raise RuntimeError, "Unknown encryption mode: #{value_encryption}"
      end
    end
    def encryption_key_v1 *ignored
      OT::Secret.encryption_key self.key, self.passphrase_temp
    end
    def encryption_key_v2 *ignored
      OT::Secret.encryption_key OT.global_secret, self.key, self.passphrase_temp
    end
    def load_customer
      cust = OT::Customer.load custid 
      cust.nil? ? OT::Customer.anonymous : cust
    end
    def state
      get_value(:state) || @state
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def viewed!
      # Make sure we don't go from :viewed to something else
      return unless state?(:new) || state?(:viewed)
      @state = 'viewed'
      update_fields :viewed => Time.now.utc.to_i, :state => :viewed
      self.incr :view_count
      if maxviews?
        self.delete :value
        self.delete :passphrase
        self.delete :value_checksum
        self.delete :original_size
        @passphrase_temp = nil
      end
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
      def create custid, extra_entropy=[]
        entropy = [OT.instance, Time.now.to_f, OT.entropy, extra_entropy].flatten
        obj = new custid, entropy
        # force the storing of the fields to redis
        obj.update_fields :custid => custid # calls update_time!
        obj
      end
      def spawn_pair custid, extra_entropy
        entropy = [OT.instance, Time.now.to_f, OT.entropy, extra_entropy].flatten
        metadata, secret = OT::Metadata.new(custid, entropy), OT::Secret.new(custid, entropy)
        metadata.secret_key = secret.key
        [metadata, secret]
      end
      def encryption_key *entropy
        input = entropy.flatten.compact.join ':'
        ret = Digest::SHA256.hexdigest(input)
      end
    end
  end
end