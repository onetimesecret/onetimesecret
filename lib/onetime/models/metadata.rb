
module Onetime
  class Metadata < Familia::HashKey
    include Onetime::Models::RedisHash
    include Gibbler::Complex
    #prefix :metadata
    #index :key
    #field :key
    #field :custid
    #field :state
    #field :secret_key
    #field :passphrase
    #field :viewed => Integer
    #field :shared => Integer
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :custid, :secret_key, :entropy
    def initialize custid=nil, entropy=[]
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
    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end
    def older_than? seconds
      age > seconds
    end
    def valid?
      exists?
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return if state?(:viewed) || state?(:shared)
      update_fields :state => :viewed, :viewed => Time.now.utc.to_i
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def shared!
      update_fields :state => :shared, :shared => Time.now.utc.to_i, :secret_key => nil
    end
    def load_secret
      OT::Secret.load secret_key
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
    end
  end
end