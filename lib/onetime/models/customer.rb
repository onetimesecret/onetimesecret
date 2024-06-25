

class Onetime::Customer < Familia::HashKey
  @values = Familia::SortedSet.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, :db => 6

  include Onetime::Models::RedisHash
  include Onetime::Models::Passphrase

  def initialize custid=:anon
    @custid = custid  # if we use accessor methods it will sync to redis.
    super name, :db => 6
  end

  def identifier
    @custid
  end

  def contributor?
    self.contributor.to_s == "true"
  end

  def apitoken? guess
    self.apitoken.to_s == guess.to_s
  end

  def regenerate_apitoken
    self.apitoken = [OT.instance, OT.now.to_f, :apikey, custid].gibbler
  end

  def get_persistent_value sess, n
    (anonymous? ? sess : self)[n]
  end

  def set_persistent_value sess, n, v
    (anonymous? ? sess : self)[n] = v
  end

  def external_identifier
    if anonymous?
      raise OT::Problem, "Anonymous customer has no external identifier"
    end
    elements = [custid]
    @external_identifier ||= elements.gibbler
    @external_identifier
  end

  def anonymous?
    custid.to_s.eql?('anon')
  end

  def email
    @custid
  end

  def role
    self.get_value(:role) || 'customer'
  end

  def role? guess
    role.to_s.eql?(guess.to_s)
  end

  def verified?
    !anonymous? && verified.to_s.eql?('true')
  end

  def active?
    # We modify the role when destroying so if a customer is verified
    # and has a role of 'customer' then they are active.
    verified? && role?('customer')
  end

  def pending?
    # A customer is considered pending if they are not anonymous, not verified,
    # and have a role of 'customer'. If any one of these conditions is changes
    # then the customer is no longer pending.
    !anonymous? && !verified? && role?('customer')  # we modify the role when destroying
  end

  def load_session
    OT::Session.load sessid unless sessid.to_s.empty?
  end

  def load_subdomain
    OT::Subdomain.load custid unless custid.to_s.empty?
  end

  def metadata_list
    if @metadata_list.nil?
      el = [prefix, identifier, :metadata]
      el.unshift Familia.apiversion unless Familia.apiversion.nil?
      @metadata_list = Familia::SortedSet.new Familia.join(el), :db => db
    end
    @metadata_list
  end

  def metadata
    metadata_list.revmembers.collect { |key| OT::Metadata.load key }.compact
  end

  def add_metadata s
    metadata_list.add OT.now.to_i, s.key
  end

  def update_passgen_token v
    self['passgen_token'] = v.encrypt(:key => encryption_key)
  end

  def passgen_token
    self['passgen_token'].decrypt(:key => encryption_key) if has_key?(:passgen_token)
  end

  def encryption_key
    OT::Secret.encryption_key OT.global_secret, custid
  end

  def destroy_requested!
    # NOTE: we don't use cust.destroy! here since we want to keep the
    # customer record around for a grace period to take care of any
    # remaining business to do with the account.
    #
    # We do however auto-expire the customer record after
    # the grace period.
    #
    # For example if we need to send a pro-rated refund
    # or if we need to send a notification to the customer
    # to confirm the account deletion.
    self.ttl = 7.days
    self.regenerate_apitoken
    self.passphrase = ''
    self.verified = 'false'
    self.role = 'user_deleted_self'
    save
  end

  module ClassMethods
    attr_reader :values
    def add cust
      self.values.add OT.now.to_i, cust.identifier
    end
    def all
      self.values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
    end
    def recent duration=30.days, epoint=OT.now.to_i
      spoint = OT.now.to_i-duration
      self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
    end
    def global
      if @global.nil?
        @global = exists?(:GLOBAL) ? load(:GLOBAL) : create(:GLOBAL)
        @global.secrets_created ||= 0
        @global.secrets_shared  ||= 0
      end
      @global
    end

    def anonymous
      cust = new
    end
    def exists? custid
      cust = new custid
      cust.exists?
    end
    def load custid
      cust = new custid
      cust.exists? ? cust : nil
    end
    def create custid, email=nil
      cust = new custid
      # force the storing of the fields to redis
      cust.custid = custid
      cust.role = 'customer'
      cust.save
      add cust
      cust
    end
  end

  extend ClassMethods
end
