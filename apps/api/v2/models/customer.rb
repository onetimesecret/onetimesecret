# apps/api/v2/models/customer.rb

require 'rack/utils'

require_relative 'mixins/passphrase'

module V2
  class Customer < Familia::Horreum
    include Gibbler::Complex

    @global = nil

    feature :safe_dump
    feature :expiration

    prefix :customer

    class_sorted_set :values, key: 'onetime:customer'
    class_hashkey :domains, key: 'onetime:customers:domain'

    sorted_set :custom_domains, suffix: 'custom_domain'
    sorted_set :metadata

    hashkey :feature_flags # To turn on allow_public_homepage column in domains table

    # Used to track the current and most recently created password reset secret.
    string :reset_secret, ttl: 24.hours

    identifier :custid

    field :custid
    field :email
    field :role
    field :sessid
    field :apitoken # TODO: use sorted set?
    field :verified

    field :locale

    field :secrets_created # regular hashkey string field
    field :secrets_burned
    field :secrets_shared
    field :emails_sent

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
      { :identifier => ->(obj) { obj.identifier } },
      :custid,
      :email,

      :role,
      :verified,
      :last_login,
      :locale,
      :updated,
      :created,

      :stripe_customer_id,
      :stripe_subscription_id,
      :stripe_checkout_email,

      :planid,

      # NOTE: The secrets_created incrementer is null until the first secret
      # is created. See ConcealSecret for where the incrementer is called.
      #
      {:secrets_created => ->(cust) { cust.secrets_created.to_s || 0 } },
      {:secrets_burned => ->(cust) { cust.secrets_burned.to_s || 0 } },
      {:secrets_shared => ->(cust) { cust.secrets_shared.to_s || 0 } },
      {:emails_sent => ->(cust) { cust.emails_sent.to_s || 0 } },

      # We use the hash syntax here since `:active?` is not a valid symbol.
      { :active => ->(cust) { cust.active? } },
    ]

    def init
      self.custid ||= 'anon'
      self.role ||= 'customer'
      self.email ||= self.custid unless anonymous?

      # When an instance is first created, any field that doesn't have a
      # value set will be nil. We need to ensure that these fields are
      # set to an empty string to match the default values when loading
      # from redis (i.e. all values in core redis data types are strings).
      self.locale ||= ''

      # Initialze auto-increment fields. We do this since Redis
      # gets grumpy about trying to increment a hashkey field
      # that doesn't have any value at all yet. This is in
      # contrast to the regular INCR command where a
      # non-existant key will simply be set to 1.
      self.secrets_created ||= 0
      self.secrets_burned ||= 0
      self.secrets_shared ||= 0
      self.emails_sent ||= 0
    end

    def contributor?
      self.contributor.to_s == "true"
    end

    def locale?
      !locale.to_s.empty?
    end

    def apitoken? guess
      self.apitoken.to_s == guess.to_s
    end

    def regenerate_apitoken
      self.apitoken! [OT.instance, OT.now.to_f, :apitoken, custid].gibbler
      self.apitoken # the fast writer bang methods don't return the value
    end


    def get_stripe_customer
      get_stripe_customer_by_id || get_stripe_customer_by_email
    rescue Stripe::StripeError => e
      OT.le "[Customer.get_stripe_customer] Error: #{e.message}: #{e.backtrace}"
      nil
    end

    def get_stripe_subscription
      get_stripe_subscription_by_id || get_stripe_subscriptions&.first
    end

    def get_stripe_customer_by_id customer_id=nil
      customer_id ||= stripe_customer_id
      return if customer_id.to_s.empty?
      OT.info "[Customer.get_stripe_customer_by_id] Fetching customer: #{customer_id} #{custid}"
      @stripe_customer = Stripe::Customer.retrieve(customer_id)

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
      subscription_id ||= stripe_subscription_id
      return if subscription_id.to_s.empty?
      OT.info "[Customer.get_stripe_subscription_by_id] Fetching subscription: #{subscription_id} #{custid}"
      @stripe_subscription = Stripe::Subscription.retrieve(subscription_id)
    rescue Stripe::StripeError => e
      OT.le "[Customer.get_stripe_subscription_by_id] Error: #{e.message}"
      nil
    end

    def get_stripe_subscriptions stripe_customer=nil
      stripe_customer ||= @stripe_customer
      subscriptions = []
      return subscriptions unless stripe_customer

      begin
        subscriptions = Stripe::Subscription.list(customer: stripe_customer.id, limit: 1)

      rescue Stripe::StripeError => e
        OT.le "Error: #{e.message}"
      else
        if subscriptions.data.empty?
          OT.info "No subscriptions found for customer: #{stripe_customer.id}"
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
        raise Onetime::Problem, "Anonymous customer has no external identifier"
      end
      # Changing the type, order or value of the elements in this array will
      # change the external identifier. This is used to identify customers
      # primarily in logs and other external systems where the actual customer
      # ID is not needed or otherwise not appropriate to use. Keeping the
      # value consistent is generally preferred.
      elements = ['cust', role, custid]
      @external_identifier ||= elements.gibbler
      @external_identifier
    end

    def anonymous?
      custid.to_s.eql?('anon')
    end

    def global?
      custid.to_s.eql?('GLOBAL')
    end

    def obscure_email
      if anonymous?
        'anon'
      else
        OT::Utils.obscure_email(custid)
      end
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

    def reset_secret? secret
      return false if secret.nil? || !secret.exists? || secret.key.to_s.empty?
      Rack::Utils.secure_compare(self.reset_secret.to_s, secret.key)
    end

    def valid_reset_secret! secret
      if is_valid = reset_secret?(secret)
        OT.ld "[valid_reset_secret!] Reset secret is valid for #{custid} #{secret.shortkey}"
        secret.delete!
        self.reset_secret.delete!
      end
      is_valid
    end

    # Loads an existing session or creates a new one if it doesn't exist.
    #
    # @param [String] ip_address The IP address of the customer.
    # @raise [Onetime::Problem] if the customer is anonymous.
    # @return [V2::Session] The loaded or newly created session.
    def load_or_create_session(ip_address)
      raise Onetime::Problem, "Customer is anonymous" if anonymous?
      @sess = V2::Session.load(sessid) unless sessid.to_s.empty?
      if @sess.nil?
        @sess = V2::Session.create(ip_address, custid)
        sessid = @sess.identifier
        OT.info "[load_or_create_session] adding sess #{sessid} to #{obscure_email}"
        self.sessid!(sessid)
      end
      @sess
    end

    def metadata_list
      metadata.revmembers.collect do |key|
        obj = V2::Metadata.load(key)
      rescue Onetime::RecordNotFound => e
        OT.le "[metadata_list] Error: #{e.message} (#{key} / #{self.custid})"
      end.compact
    end

    def add_metadata obj
      metadata.add OT.now.to_i, obj.key
    end

    def custom_domains_list
      custom_domains.revmembers.collect do |domain|
        V2::CustomDomain.load domain, self.custid
      rescue Onetime::RecordNotFound => e
        OT.le "[custom_domains_list] Error: #{e.message} (#{domain} / #{self.custid})"
      end.compact
    end

    def add_custom_domain obj
      OT.ld "[add_custom_domain] adding #{obj} to #{self}"
      custom_domains.add OT.now.to_i, obj.display_domain # not the object identifier
    end

    def remove_custom_domain obj
      custom_domains.remove obj.display_domain # not the object identifier
    end

    def encryption_key
      V2::Secret.encryption_key OT.global_secret, custid
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
      self.destroy_requested
      save
    end

    def destroy_requested
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
    # @raise [Onetime::Problem] If attempting to save an anonymous customer.
    # @return [Boolean] Returns true if the save was successful.
    #
    # This method overrides the default save behavior to prevent
    # anonymous customers from being persisted to the database.
    def save **kwargs
      raise Onetime::Problem, "Anonymous cannot be saved #{self.class} #{rediskey}" if anonymous?
      super(**kwargs)
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

    def increment_field field
      if anonymous?
        whereami = caller(1..4)
        OT.le "[increment_field] Refusing to increment #{field} for anon customer #{whereami}"
        return
      end

      # Taking the module Approach simply to keep it out of this busy Customer
      # class. There's a small benefit to being able grep for "cust.method_name"
      # which this approach affords as well. Although it's a small benefit.
      self.class.increment_field(self, field)
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
        new('anon').freeze
      end

      def create custid, email=nil
        raise Onetime::Problem, "custid is required" if custid.to_s.empty?
        raise Onetime::Problem, "Customer exists" if exists?(custid)
        cust = new custid: custid, email: email || custid, role: 'customer'
        cust.save
        add cust
        cust
      end

      def global
        @global ||= from_identifier(:GLOBAL) || create(:GLOBAL)
        @global
      end

      def increment_field(cust, field)
        return if cust.global?
        curval = cust.send(field)
        OT.info "[increment_field] cust.#{field} is #{curval} for #{cust}"

        cust.increment field

      rescue Redis::CommandError => e

        # For whatever reason, redis throws an error when trying to
        # increment a non-existent hashkey field (rather than setting
        # it to 1): "ERR hash value is not an integer"
        OT.le "[increment_field] Redis error (#{curval}): #{e.message}"

        # So we'll set it to 1 if it's empty. It's possible we're here
        # due to a different error, but this value needs to be
        # initialized either way.
        cust.send("#{field}!", 1) if curval.to_i.zero? # nil and '' cast to 0
      end
    end

    # Mixin Placement for Field Order Control
    #
    # We include the SessionMessages mixin at the end of this class definition
    # for a specific reason related to how Familia::Horreum handles fields.
    #
    # In Familia::Horreum subclasses (like this Customer class), fields are processed
    # in the order they are defined. When creating a new instance with Session.new,
    # any provided positional arguments correspond to these fields in the same order.
    #
    # By including SessionMessages last, we ensure that:
    # 1. Its additional fields appear at the end of the field list.
    # 2. These fields don't unexpectedly consume positional arguments in Session.new.
    #
    # e.g. `Customer.new('my@example.com')`. If we included thePassphrase
    # module at the top, instead of populating the custid field (as the
    # first field defined in this file), this email address would get
    # written to the (automatically inserted) passphrase field.
    #
    include V2::Mixins::Passphrase
    extend ClassMethods
  end
end
