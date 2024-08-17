

class Onetime::Customer < Familia::Horreum
  include Gibbler::Complex

  db 6
  prefix :customer

  feature :safe_dump

  class_sorted_set :values, key: 'onetime:customers'
  class_hashkey :domains, key: 'onetime:customers:domains'
  class_hashkey :global, key: 'customer:GLOBAL:object'

  sorted_set :custom_domains_list
  sorted_set :metadata_list

  identifier :custid

  field :custid
  field :email
  field :key
  field :role
  field :sessid
  field :apitoken
  field :verified
  field :secrets_created # regular hashkey string field
  field :planid
  field :created
  field :updated
  field :last_login
  field :contributor

  field :stripe_customer_id
  field :stripe_subscription_id
  field :stripe_checkout_email

  # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
  # with hot reloading in dev mode will not work. You will need to restart the
  # server to see the changes.
  @safe_dump_fields = [
    :custid,
    :role,
    :verified,
    :last_login,
    :updated,
    :created,

    :stripe_customer_id,
    :stripe_subscription_id,
    :stripe_checkout_email,

    {:plan => ->(cust) { cust.load_plan } }, # safe_dump will be called automatically

    # NOTE: The secrets_created incrementer is null until the first secret
    # is created. See CreateSecret for where the incrementer is called.
    #
    {:secrets_created => ->(cust) { cust.secrets_created.to_s || 0 } },

    # We use the hash syntax here since `:active?` is not a valid symbol.
    { :active => ->(cust) { cust.active? } }
  ]

  #  def initialize custid=nil
  #    @custid = custid || :anon # if we use accessor methods it will sync to redis.
  #
  #    # WARNING: There's a gnarly bug in the awkward relationship between
  #    # RedisHash (local lib) and RedisObject (familia gem) where a value
  #    # can be set to an instance var, the in-memory cache in RedisHash,
  #    # and/or the persisted value in redis. RedisHash#method_missing
  #    # allows for calling fields as method names on the object itself;
  #    # RedisObject (specifically Familia::HashKey in this case), relies
  #    # on `[]` and `[]=` to access and set values in redis.
  #    #
  #    # The problem is that the value set by RedisHash#method_missing
  #    # is not available to RedisObject (Familia::HashKey) until after
  #    # the object has been initialized and `super` called in RedisObject.
  #    # Long story short: we set these two instance vars do that the
  #    # identifier method can produce a valid identifier string. But,
  #    # we're relying on Customer.create to duplicate the effort
  #    # and set the same values in the way that will persist them to
  #    # redis. Hopefully I do'nt find myself reading this comment in
  #    # 5 years and wondering why I can't just call `super` man.
  #
  #    super name, db: 6 # `name` here refers to `RedisHash#name`
  #  end

  def init
    self.custid ||= :anon
    self.role ||= 'customer'
  end

  def name
    rediskey # backwards compat for Familia v0.10.2
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

  def load_plan
    Onetime::Plan.plan(planid) || {:planid => planid, :source => 'parts_unknown'}
  end

  def get_stripe_customer
    get_stripe_customer_by_id || get_stripe_customer_by_email
  end

  def get_stripe_subscription
    get_stripe_subscription_by_id || get_stripe_subscriptions&.first
  end

  def get_stripe_customer_by_id customer_id=nil
    return unless stripe_customer_id || customer_id
    @stripe_customer = Stripe::Customer.retrieve(stripe_customer_id || customer_id)

  rescue Stripe::StripeError => e
    OT.le "[Customer.get_stripe_customer_by_id] Error: #{e.message}"
    nil
  end

  def get_stripe_customer_by_email
    customers = Stripe::Customer.list(email: email, limit: 1)

    if customers.data.empty?
      OT.info "[Customer.get_stripe_customer_by_email] No customer found with email: #{email}"

    else
      @stripe_customer = customers.data.first
      OT.info "[Customer.get_stripe_customer_by_email] Customer found: #{@stripe_customer.id}"
    end

    @stripe_customer

  rescue Stripe::StripeError => e
    OT.le "[Customer.get_stripe_customer_by_email] Error: #{e.message}"
    nil
  end

  def get_stripe_subscription_by_id subscription_id=nil
    return unless stripe_subscription_id || subscription_id
    @stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id || subscription_id)
  end

  def get_stripe_subscriptions stripe_customer=nil
    stripe_customer ||= @stripe_customer
    subscriptions = []
    return subscriptions unless stripe_customer

    begin
      subscriptions = Stripe::Subscription.list(customer: stripe_customer.id, limit: limit)

    rescue Stripe::StripeError => e
      OT.le "Error: #{e.message}"
    else
      if subscriptions.data.empty?
        OT.info "No subscriptions found for customer: #{customer_id}"
      else
        OT.info "Found #{subscriptions.data.length} subscriptions"
        subscriptions = subscriptions.data
      end
    end

    subscriptions
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
    custid.to_s.to_sym.eql?(:anon)
  end

  def obscure_email
    if anonymous?
      'anon'
    else
      OT::Utils.obscure_email(custid)
    end
  end

  def email
    @custid
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

  def metadata
    metadata_list.revmembers.collect { |key| OT::Metadata.load key }.compact
  end

  def add_metadata obj
    metadata_list.add OT.now.to_i, obj.key
  end

  def custom_domains
    custom_domains_list.revmembers.collect { |domain| OT::CustomDomain.load domain, self.custid }.compact
  end

  def add_custom_domain obj
    OT.ld "[add_custom_domain] adding #{obj} to #{self}"
    custom_domains_list.add OT.now.to_i, obj.display_domain # not the object identifier
  end

  def remove_custom_domain obj
    custom_domains_list.rem obj.display_domain # not the object identifier
  end

  def update_passgen_token v
    self.passgen_token = v.encrypt(:key => encryption_key)
  end

  def passgen_token
    self.passgen_token.decrypt(:key => encryption_key) if has_key?(:passgen_token)
  end

  def encryption_key
    OT::Secret.encryption_key OT.global_secret, custid
  end

  # Marks the customer account as requested for destruction.
  #
  # This method doesn't actually destroy the customer record but prepares it
  # for eventual deletion after a grace period. It performs the following actions:
  #
  # 1. Sets a Time To Live (TTL) of 365 days on the customer record.
  # 2. Regenerates the API token.
  # 3. Clears the passphrase.
  # 4. Sets the verified status to 'false'.
  # 5. Changes the role to 'user_deleted_self'.
  #
  # The customer record is kept for a grace period to handle any remaining
  # account-related tasks, such as pro-rated refunds or sending confirmation
  # notifications.
  #
  # @return [void]
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
    self.ttl = 365.days
    self.regenerate_apitoken
    self.passphrase = ''
    self.verified = 'false'
    self.role = 'user_deleted_self'
    save
  end

  # Saves the customer object to the database.
  #
  # @raise [OT::Problem] If attempting to save an anonymous customer.
  # @return [Boolean] Returns true if the save was successful.
  #
  # This method overrides the default save behavior to prevent
  # anonymous customers from being persisted to the database.
  def save
    raise OT::Problem, "Anonymous cannot be saved #{self.class} #{rediskey}" if anonymous?
    super
  end

  def to_s
    # If we can treat familia objects as strings, then passing them as method
    # arguments we don't need to check whether it is_a? RedisObject or not;
    # we can simply call `custid.to_s`. In both cases the result is the unqiue
    # ID of the familia object. Usually that is all we need to maintain the
    # relation records -- we don't actually need the instance of the familia
    # object itself. So there's no need to hydrate the familia object from the
    # unless we need to access the object's attributes (e.g., for logging or
    # debugging purposes or modifying/manipulating the object's attributes).
    #
    # As a pilot for the project, CustomDomain has the equivalent method and
    # comment. See the CustomDomain class methods for usage details.
    identifier.to_s
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

    def anonymous
      new(:anon).freeze
    end

    def exists? custid
      cust = new custid: custid
      cust.exists?
    end

    def load custid
      from_redis custid
    end

    def create custid, email=nil
      raise OT::Problem, "custid is required" if custid.to_s.empty?
      raise OT::Problem, "Customer exists" if exists?(custid)
      cust = new custid: custid, role: 'customer'
      cust.email = email || custid
      cust.save
      add cust
      cust
    end
  end

  # We include this at the end so that the added fields
  # appear at the end of the field list instead of the
  # very start. This avoids the subtle behaviour where
  # Customer.new (or any Familia::Horreum subclass)
  # accepts positional arguments in the order they
  # are defined at the top of the class definition.
  #
  # e.g. `Customer.new('my@example.com')`. If we include
  # Passphrase at the top, instead of custid, this email
  # address would get written to the passphrase field.
  #
  include Onetime::Models::Passphrase
  extend ClassMethods
end
