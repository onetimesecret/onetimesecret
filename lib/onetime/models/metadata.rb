
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
    gibbler :custid, :secret_key, :entropy
    def initialize custid=nil, entropy=[]
      @custid, @entropy, @state = custid, entropy, :new
      @key = gibbler.base(36)
      super name, :db => 7, :ttl => 7.days
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
    def deliver_by_email cust, secret, eaddrs
      if eaddrs.nil? || eaddrs.empty?
        OT.info "[deliver-by-email] No addresses specified"
      end
      eaddrs = [eaddrs].flatten.compact[0..9] # Max 10
      eaddrs_safe = eaddrs.collect { |e| OT::Utils.obscure_email(e) }
      self.recipients = eaddrs_safe.join(', ')
      eaddrs.each do |email_address|
        view = OT::Email::SecretLink.new cust, secret, email_address
        ret = view.deliver_email
        if ret.code == 200
          cust.incr :emails_sent
          OT::Customer.global.incr :emails_sent
        else
          OT.info "Error sending email: #{ret}"
        end
      end
    end
    def older_than? seconds
      age > seconds
    end
    def valid?
      exists?
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return unless state?(:new)
      @state = :viewed
      update_fields :state => :viewed, :viewed => Time.now.utc.to_i
    end
    def received!
      # Make sure we don't go from :shared to :viewed
      return unless state?(:new) || state?(:viewed)
      @state = :received
      update_fields :state => :received, :received => Time.now.utc.to_i, :secret_key => nil
    end
    def state? guess
      state.to_s == guess.to_s
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