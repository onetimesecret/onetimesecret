# apps/api/v2/models/customer.rb

require 'rack/utils'

require_relative 'customer/features'

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
    feature :relationships
    feature :object_identifiers
    feature :required_fields
    feature :increment_field
    feature :right_to_be_forgotten
    feature :with_stripe_account
    feature :with_custom_domains
    feature :customer_status

    feature :customer_deprecated_fields
    feature :legacy_encrypted_fields
    feature :legacy_secrets_fields

    def anonymous?
      custid.to_s.eql?('anon')
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

    # Saves the customer object to the database.
    #
    # @raise [Onetime::Problem] If attempting to save an anonymous customer.
    # @return [Boolean] Returns true if the save was successful.
    #
    # This method overrides the default save behavior to prevent
    # anonymous customers from being persisted to the database.
    def save(**)
      raise Onetime::Problem, "Anonymous cannot be saved #{self.class} #{dbkey}" if anonymous?

      super
    end

    class << self
      attr_reader :values

      def create(custid, email = nil)
        raise Onetime::Problem, 'custid is required' if custid.to_s.empty?
        raise Onetime::Problem, 'Customer exists' if exists?(custid)

        cust        = new custid: custid, email: email || custid, role: 'customer'
        cust.planid = 'basic'
        OT.ld "[create] custid: #{custid}, #{cust.safe_dump}"
        cust.save
        add cust
        cust
      end

      def anonymous
        new('anon').freeze
      end

      def add(cust)
        values.add OT.now.to_i, cust.identifier
      end

      def all
        values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i - duration
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def global
        @global ||= from_identifier(:GLOBAL) || create(:GLOBAL)
        @global
      end

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded random string
      def generate_id
        OT::Utils.generate_id
      end
    end
  end
end
