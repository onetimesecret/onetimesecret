# apps/api/v2/models/customer.rb

require 'rack/utils'

require_relative 'definitions/customer_definition'

module V2
  # Customer Model (aka User)
  #
  # IMPORTANT API CHANGES:
  # Previously, anonymous users were identified by custid='anon'.
  # Now we use user_type='anonymous' as the primary indicator.
  #
  # USAGE:
  # - Authenticated: Customer.create(custid, email)
  # - Anonymous: Customer.anonymous
  # - Explicit: Customer.new(custid: 'email', user_type: 'authenticated')
  #
  # AVOID: Customer.new('email@example.com') - creates anonymous user with email
  #
  # STATES:
  # - anonymous?: user_type == 'anonymous' || custid == 'anon'
  # - verified?: authenticated + verified == 'true'
  # - active?: verified + role == 'customer'
  # - pending?: authenticated + !verified + role == 'customer'
  #
  # The init method sets user_type: 'anonymous' by default to maintain
  # backwards compatibility, but business logic should use the explicit
  # factory methods above to avoid state inconsistencies.
  #
  class Customer < Familia::Horreum
    def locale?
      !locale.to_s.empty?
    end

    def apitoken?(guess)
      apitoken.to_s == guess.to_s
    end

    def regenerate_apitoken
      apitoken! OT::Utils.generate_id
      apitoken # the fast writer bang methods don't return the value
    end

    def external_identifier
      raise OT::Problem, 'Anonymous customer has no external identifier' if anonymous?

      @external_identifier ||= OT::Utils.generate_id # generate but don't save
      @external_identifier
    end

    def get_stripe_customer
      get_stripe_customer_by_id || get_stripe_customer_by_email
    rescue Stripe::StripeError => ex
      OT.le "[Customer.get_stripe_customer] Error: #{ex.message}: #{ex.backtrace}"
      nil
    end

    def get_stripe_subscription
      get_stripe_subscription_by_id || get_stripe_subscriptions&.first
    end

    def get_stripe_customer_by_id(customer_id = nil)
      customer_id ||= stripe_customer_id
      return if customer_id.to_s.empty?

      OT.info "[Customer.get_stripe_customer_by_id] Fetching customer: #{customer_id} #{custid}"
      @stripe_customer = Stripe::Customer.retrieve(customer_id)
    rescue Stripe::StripeError => ex
      OT.le "[Customer.get_stripe_customer_by_id] Error: #{ex.message}"
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
    rescue Stripe::StripeError => ex
      OT.le "[Customer.get_stripe_customer_by_email] Error: #{ex.message}"
      nil
    end

    def get_stripe_subscription_by_id(subscription_id = nil)
      subscription_id ||= stripe_subscription_id
      return if subscription_id.to_s.empty?

      OT.info "[Customer.get_stripe_subscription_by_id] Fetching subscription: #{subscription_id} #{custid}"
      @stripe_subscription = Stripe::Subscription.retrieve(subscription_id)
    rescue Stripe::StripeError => ex
      OT.le "[Customer.get_stripe_subscription_by_id] Error: #{ex.message}"
      nil
    end

    def get_stripe_subscriptions(stripe_customer = nil)
      stripe_customer ||= @stripe_customer
      subscriptions     = []
      return subscriptions unless stripe_customer

      begin
        subscriptions = Stripe::Subscription.list(customer: stripe_customer.id, limit: 1)
      rescue Stripe::StripeError => ex
        OT.le "Error: #{ex.message}"
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

    def role?(guess)
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
      !anonymous? && !verified? && role?('customer') # we modify the role when destroying
    end

    def reset_secret?(secret)
      return false if secret.nil? || !secret.exists? || secret.key.to_s.empty?

      Rack::Utils.secure_compare(reset_secret.to_s, secret.key)
    end

    def valid_reset_secret!(secret)
      if is_valid = reset_secret?(secret)
        OT.ld "[valid_reset_secret!] Reset secret is valid for #{custid} #{secret.shortkey}"
        secret.delete!
        reset_secret.delete!
      end
      is_valid
    end

    # Loads an existing session or creates a new one if it doesn't exist.
    #
    # @param [String] ip_address The IP address of the customer.
    # @raise [Onetime::Problem] if the customer is anonymous.
    # @return [V2::Session] The loaded or newly created session.
    def load_or_create_session(ip_address)
      raise Onetime::Problem, 'Customer is anonymous' if anonymous?

      @sess = V2::Session.load(sessid) unless sessid.to_s.empty?
      if @sess.nil?
        @sess  = V2::Session.create(ip_address, custid)
        sessid = @sess.identifier
        OT.info "[load_or_create_session] adding sess #{sessid} to #{obscure_email}"
        sessid!(sessid)
      end
      @sess
    end

    def metadata_list
      metadata.revmembers.collect do |key|
        V2::Metadata.load(key)
      rescue Onetime::RecordNotFound => ex
        OT.le "[metadata_list] Error: #{ex.message} (#{key} / #{custid})"
      end.compact
    end

    def add_metadata(obj)
      metadata.add OT.now.to_i, obj.key
    end

    def custom_domains_list
      custom_domains.revmembers.collect do |domain|
        V2::CustomDomain.load domain, custid
      rescue Onetime::RecordNotFound => ex
        OT.le "[custom_domains_list] Error: #{ex.message} (#{domain} / #{custid})"
      end.compact
    end

    def add_custom_domain(obj)
      OT.ld "[add_custom_domain] adding #{obj} to #{self}"
      custom_domains.add OT.now.to_i, obj.display_domain # not the object identifier
    end

    def remove_custom_domain(obj)
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
      destroy_requested
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
      self.ttl        = 365.days
      regenerate_apitoken
      self.passphrase = ''
      self.verified   = 'false'
      self.role       = 'user_deleted_self'
      save
    end

    # Saves the customer object to the database.
    #
    # @raise [Onetime::Problem] If attempting to save an anonymous customer.
    # @return [Boolean] Returns true if the save was successful.
    #
    # This method overrides the default save behavior to prevent
    # anonymous customers from being persisted to the database.
    def save(**)
      raise Onetime::Problem, "Anonymous cannot be saved #{self.class} #{rediskey}" if anonymous?

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

    def increment_field(field)
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
  end
end

require_relative 'management/customer_management'
