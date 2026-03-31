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
  # ANONYMOUS USER HANDLING (PR #2733):
  # Anonymous/unauthenticated requests now use `cust = nil` instead of a
  # Customer.anonymous singleton. This simplifies authorization logic:
  #   - Check `cust.nil? || cust.anonymous?` or use `anonymous_user?(cust)` helper
  #   - The `anonymous?` method checks `role == 'anonymous'`
  #   - Historical data compatibility: Receipt/Secret check `owner_id == 'anon'`
  #
  # USAGE:
  # - Authenticated: Customer.create!(custid, email)
  # - Anonymous: nil (no Customer object)
  #
  # STATES:
  # - anonymous?: role == 'anonymous'
  # - verified?: authenticated + verified == 'true'
  # - active?: verified + role == 'customer'
  # - pending?: authenticated + !verified + role == 'customer'
  #
  # Opaque Identifier Pattern (OWASP IDOR Prevention):
  # Uses dual-ID system to prevent enumeration attacks in URLs/APIs.
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

    SCHEMA = 'models/customer'

    require_relative 'customer/features'

    using Familia::Refinements::TimeLiterals

    prefix :customer

    feature :expiration
    feature :relationships
    feature :object_identifier
    feature :external_identifier, format: 'ur%<id>s' # use builtin extid_lookup index
    feature :required_fields
    feature :increment_field
    feature :counter_fields
    feature :right_to_be_forgotten
    feature :safe_dump_fields
    feature :with_custom_domains
    feature :status
    feature :role_index

    feature :deprecated_fields
    feature :legacy_encrypted_fields
    feature :legacy_secrets_fields

    # Migration features - REMOVE after v1→v2 migration complete
    feature :with_migration_fields
    feature :customer_migration_fields

    sorted_set :receipts
    hashkey :feature_flags # To turn on allow_public_homepage column in domains table

    # Used to track the current and most recently created password reset secret.
    string :reset_secret, default_expiration: 24.hours

    # Used to track a pending email change verification secret.
    string :pending_email_change, default_expiration: 24.hours

    # Tracks delivery status of the pending email change confirmation email.
    # Values: queued, sent, failed. Expires with the pending change.
    string :pending_email_delivery_status, default_expiration: 24.hours

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

    # Participation - bidirectional membership tracking with reverse indexes
    # Organization: org.members gives O(1) access to all members
    # Through model auto-creates OrganizationMembership with role, status, etc.
    participates_in :Organization, :members, score: :joined, through: Onetime::OrganizationMembership

    field_group :core_fields do
      field :custid
      field :email
    end

    field :locale
    field :planid

    field :last_password_update
    field :last_login

    # Notification preferences
    field :notify_on_reveal  # Boolean string: 'true' or 'false'

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

    # Checks if this customer has the anonymous role. Previously also checked
    # custid == 'anon' sentinel, but that detection was removed in favor of
    # explicit nil checks at call sites (cust.nil? || cust.anonymous?).
    def anonymous?
      role.to_s.eql?('anonymous')
    end

    def obscure_email
      return 'anonymous@example.com' if anonymous?

      OT::Utils.obscure_email(email)
    end

    def role?(guess)
      role.to_s.eql?(guess.to_s)
    end

    # Check if user wants notification when their secret is revealed
    # @return [Boolean] true if notifications enabled, false otherwise (default)
    def notify_on_reveal?
      notify_on_reveal.to_s == 'true'
    end

    # Allowlist of fields accessible via hash-like [] access.
    # This restricts access to prevent arbitrary method invocation.
    # See Otto's RouteAuthWrapper#extract_user_roles for usage context.
    HASH_ACCESSIBLE_FIELDS = [
      :role, :roles, :email, :custid, :objid, :user_id, :planid, :locale, :created
    ].freeze

    # Hash-like accessor for Otto's RouteAuthWrapper#extract_user_roles
    #
    # Otto expects user objects to support hash-like access via [] method.
    # This allows Otto to extract roles from the user object when metadata
    # is not available or as a fallback mechanism.
    #
    # Security: Only allowlisted fields can be accessed. This prevents
    # arbitrary method invocation that was previously possible via send().
    #
    # @param key [Symbol, String] Field name to access
    # @return [Object, nil] Field value or nil if field not in allowlist
    def [](key)
      key = key.to_sym if key.is_a?(String)
      return nil unless HASH_ACCESSIBLE_FIELDS.include?(key)

      # Handle :roles as an alias for :role (Otto expects roles array)
      key = :role if key == :roles

      send(key)
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

    def apitoken?(value)
      return false if apitoken.to_s.empty? || value.to_s.empty?

      Rack::Utils.secure_compare(apitoken, value)
    end

    class << self
      attr_reader :values, :dummy

      def create!(email = nil, **kwargs)
        # Handle both positional email argument (legacy) and keyword argument
        email ||= kwargs[:email] || kwargs['email']

        # Normalize email to lowercase for consistent storage and Redis lookups.
        # Redis hash keys (unique_index :email) are case-sensitive, so we must
        # store emails consistently lowercase. Uses NFC normalization for
        # consistent Unicode representation and :fold for proper case folding
        # of international characters.
        email = email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)

        loggable_email = OT::Utils.obscure_email(email)
        raise Familia::Problem, 'email is required' if email.empty?

        raise Familia::RecordExistsError, "Customer exists #{loggable_email}" if email_exists?(email)

        Onetime.auth_logger.info 'Creating customer',
          {
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

        Onetime.auth_logger.info 'Customer created successfully',
          {
            customer_id: cust.custid,
            email: loggable_email,
            role: cust.role,
            action: 'create',
            result: :success,
          }

        cust
      end

      def load_by_extid_or_email(extid_or_email)
        find_by_extid(extid_or_email) || find_by_email(extid_or_email)
      end

      def email_exists?(email)
        Customer.email_index.key?(email)
      end

      def count
        instances.count # e.g. zcard dbkey
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
            dummy_cust.argon2_hash_cost,
          )
          dummy_cust.freeze
        end
      end
    end
  end
end
