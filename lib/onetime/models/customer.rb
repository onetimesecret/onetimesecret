# lib/onetime/models/customer.rb
#
# frozen_string_literal: true

require 'rack/utils'
require 'argon2'
require 'bcrypt'

require_relative 'features'

module Onetime
  # Customer
  #
  # IMPORTANT API CHANGES:
  # Previously, anonymous users were identified by custid='anon'.
  # Now we use user_type='anonymous' as the primary indicator.
  #
  # USAGE:
  # - Authenticated: Customer.create!(custid, email)
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
  # Primary Keys & Identifiers:
  #   - objid - Primary key (UUID), internal
  #   - extid - External identifier (e.g., ur%<id>s), user-facing
  #
  # Foreign Keys:
  #   - user_id (underscore) - Foreign key field, stores the objid value
  #   - All FK relationships use objid values for indexing
  #
  # API Layer:
  #   - Public URLs/APIs should use extid for user-facing references
  #   - Use find_by_extid(extid) to convert extid → object
  #   - Internally, relationships always use objid
  #
  # Logging:
  #   - Use extid. Don't log internal IDs.
  #
  # Easy way to remember: if you can see a UUID, it's an internal ID. If
  # you can't, it's an external ID.
  #
  class Customer < Familia::Horreum
    include Onetime::LoggerMethods

    require_relative 'customer/features'

    using Familia::Refinements::TimeLiterals

    prefix :customer

    feature :expiration
    feature :relationships
    feature :object_identifier
    feature :external_identifier, format: 'ur%<id>s'
    feature :required_fields
    feature :increment_field
    feature :counter_fields
    feature :right_to_be_forgotten
    feature :safe_dump_fields
    feature :with_custom_domains
    feature :status

    feature :deprecated_fields
    feature :legacy_encrypted_fields
    feature :legacy_secrets_fields

    sorted_set :metadata
    hashkey :feature_flags # To turn on allow_public_homepage column in domains table

    # Used to track the current and most recently created password reset secret.
    string :reset_secret, default_expiration: 24.hours

    identifier_field :objid

    # Global email index
    #
    # Unique indexes are autopopulated are the finder methods are
    # available immediatley:
    #
    # e.g. Customer.find_by_email(email)
    unique_index :email, :email_index

    # Organization-scoped indexes
    unique_index :email, :email_index, within: Onetime::Organization
    unique_index :objid, :objid_index, within: Onetime::Organization
    unique_index :extid, :extid_index, within: Onetime::Organization

    # Participation - bidirectional membership tracking with reverse indexes
    # Organization: org.members gives O(1) access to all members
    participates_in :Organization, :members, score: :joined
    participates_in :Team, :members

    field_group :core_fields do
      field :custid
      field :email
    end

    field :locale
    field :planid

    field :last_login

    def init
      super

      # IMPORTANT: Use self.objid (getter) not @objid (instance variable).
      # The ObjectIdentifier feature tracks which generator was used (uuid_v7,
      # uuid_v4, hex, etc.) in @objid_generator_used for provenance tracking.
      # Accessing @objid directly bypasses the lazy generation mechanism and
      # skips provenance tracking, causing ExternalIdentifier derivation to fail.
      self.custid ||= objid # previously <=0.22, custid was email address.
      self.role   ||= 'customer'

      # When an instance is first created, any field that doesn't have a
      # value set will be nil. We need to ensure that these fields are
      # set to an empty string to match the default values when loading
      # from the db (i.e. all values in core data types are strings).
      self.locale ||= ''

      init_counter_fields
    end

    # Underscore means foreign key. This is a convenience method for semantic
    # clarity when comparing, e.g. customer.user_id == team.user_id. We name
    # it user_id to clearly differentiate it from the deprecated custid which
    # will be removed and Customer model will be renamed User.
    def user_id
      objid
    end

    def anonymous?
      role.to_s.eql?('anonymous') || custid.to_s.eql?('anon')
    end

    def obscure_email
      return 'anonymous@example.com' if anonymous?

      OT::Utils.obscure_email(email)
    end

    def role?(guess)
      role.to_s.eql?(guess.to_s)
    end

    # Hash-like accessor for Otto's RouteAuthWrapper#extract_user_roles
    #
    # Otto expects user objects to support hash-like access via [] method.
    # This allows Otto to extract roles from the user object when metadata
    # is not available or as a fallback mechanism.
    #
    # @param key [Symbol, String] Field name to access
    # @return [Object, nil] Field value or nil if field doesn't exist
    def [](key)
      key = key.to_sym if key.is_a?(String)
      send(key) if respond_to?(key)
    rescue NoMethodError
      nil
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
      attr_reader :values, :dummy

      def create!(email = nil, **kwargs)
        # Handle both positional email argument (legacy) and keyword argument
        email ||= kwargs[:email] || kwargs['email']

        loggable_email = OT::Utils.obscure_email(email)
        raise Familia::Problem, 'email is required' if email.to_s.empty?

        raise Familia::RecordExistsError, "Customer exists #{loggable_email}" if email_exists?(email)

        Onetime.auth_logger.info 'Creating customer', {
          email: loggable_email,
          kwargs: kwargs.keys,
          action: 'create',
        }

        # Ensure email is in kwargs for super
        kwargs[:email] = email
        cust           = super(**kwargs)

        # We need to explicitly call save which is obviously duplicative. The
        # built-in create! uses save_if_not_exists which for some reason is not
        # updating all unique indexes (only objid?). Likely an upstream bug.
        cust.save

        Onetime.auth_logger.info 'Customer created successfully', {
          customer_id: cust.custid,
          email: loggable_email,
          role: cust.role,
          action: 'create',
          result: :success,
        }

        cust
      end

      def email_exists?(email)
        Customer.email_index.key?(email)
      end

      def count
        instances.count # e.g. zcard dbkey
      end

      def anonymous
        @anonymous ||= begin
          anon = new(role: 'customer', custid: 'anon', objid: 'anon', extid: 'anon')
          anon.freeze
        end
      end

      # Create a dummy customer with realistic passphrase for timing consistency.
      # Uses argon2id to match the algorithm used for real password verification,
      # ensuring timing attacks cannot distinguish between existing and
      # non-existing users based on hash algorithm differences.
      def dummy
        @dummy ||= begin
          dummy_cust                       = new(role: 'anon')
          dummy_cust.passphrase_encryption = '2'
          dummy_cust.passphrase            = ::Argon2::Password.create(
            SecureRandom.hex(16),
            dummy_cust.argon2_hash_cost
          )
          dummy_cust.freeze
        end
      end
    end
  end
end
