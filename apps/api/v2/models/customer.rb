# apps/api/v2/models/customer.rb

require 'rack/utils'

require_relative 'mixins/passphrase'

module V2
  # Customer
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
    require_relative 'customer/features'
    # include Familia::Features::Autoloader

    using Familia::Refinements::TimeLiterals

    @global = nil

    prefix :customer

    class_sorted_set :values, dbkey: 'onetime:customer'

    feature :expiration
    feature :relationships
    feature :object_identifier
    feature :external_identifier
    feature :required_fields
    feature :increment_field
    feature :counter_fields
    feature :right_to_be_forgotten
    feature :safe_dump_fields
    feature :with_stripe_account
    feature :with_custom_domains
    feature :status

    feature :deprecated_fields
    feature :legacy_encrypted_fields
    feature :legacy_secrets_fields

    sorted_set :metadata
    hashkey :feature_flags # To turn on allow_public_homepage column in domains table

    # Used to track the current and most recently created password reset secret.
    string :reset_secret, default_expiration: 24.hours

    class_indexed_by :email, :email_lookup

    identifier_field :custid

    field :custid
    field :email

    field :locale
    field :planid

    field :last_login

    def init
      self.custid ||= self.objid
      self.role   ||= 'customer'

      # When an instance is first created, any field that doesn't have a
      # value set will be nil. We need to ensure that these fields are
      # set to an empty string to match the default values when loading
      # from the db (i.e. all values in core data types are strings).
      self.locale ||= ''

      self.init_counter_fields
    end

    def anonymous?
      role.to_s.eql?('anonymous')
    end

    def obscure_email
      raise Onetime::Problem, "Anonymous has no email" if anonymous?

      OT::Utils.obscure_email(email)
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
    #
    # TODO: If familia gave us validators we could remove this guard logic
    # and the custom save method altogether.
    def save(**)
      raise Onetime::Problem, "Anonymous cannot be saved #{self.class} #{dbkey}" if anonymous?

      super
    end

    class << self
      attr_reader :values

      def create(email, **)
        raise Familia::Problem, 'email is required' if email.to_s.empty?
        raise Familia::RecordExistsError, 'Customer exists' if email_exists?(email)

        cust = new(email: email, **)

        OT.ld "[create] custid: #{cust.identifier}, #{cust.safe_dump}"
        cust.save
        add cust
        cust
      end

      def anonymous
        @anonymous ||= new(role: 'anonymous').freeze
      end

      def email_exists?(email)
        !find_by_email(email).nil?
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
  end
end
