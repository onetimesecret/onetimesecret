# lib/onetime/models/customer.rb
#
# frozen_string_literal: true

require 'rack/utils'
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
      self.custid ||= objid
      self.role   ||= 'customer'

      # When an instance is first created, any field that doesn't have a
      # value set will be nil. We need to ensure that these fields are
      # set to an empty string to match the default values when loading
      # from the db (i.e. all values in core data types are strings).
      self.locale ||= ''

      init_counter_fields
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

        Onetime.auth_logger.info "Creating customer", {
          email: loggable_email,
          kwargs: kwargs.keys,
          action: 'create'
        }

        # Ensure email is in kwargs for super
        kwargs[:email] = email
        cust           = super(**kwargs)

        # We need to explicitly call save which is obviously duplicative. The
        # built-in create! uses save_if_not_exists which for some reason is not
        # updating all unique indexes (only objid?). Likely an upstream bug.
        cust.save

        Onetime.auth_logger.info "Customer created successfully", {
          customer_id: cust.custid,
          email: loggable_email,
          role: cust.role,
          action: 'create',
          result: :success
        }

        cust
      end

      def email_exists?(email)
        Customer.email_index.key?(email)
      end

      def anonymous
        @anonymous ||= begin
          anon = new(role: 'customer', custid: 'anon', objid: 'anon', extid: 'anon')
          anon.freeze
        end
      end

      # Create a dummy customer with realistic passphrase for timing consistency
      def dummy
        @dummy ||= begin
          # Create a dummy customer with a proper BCrypt hash
          # This ensures constant-time comparison in passphrase? method
          dummy_cust                       = new(role: 'anon')
          dummy_cust.passphrase_encryption = '1'
          dummy_cust.passphrase            = BCrypt::Password.create(SecureRandom.hex(16), cost: 12).to_s
          dummy_cust.freeze
        end
      end
    end
  end
end
