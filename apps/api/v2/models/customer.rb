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

    identifier_field :objid

    # Participation: Track membership with permission encoding in score
    # → Customer: in_organization_members?(org), add_to_organization_members(org, score),
    #             remove_from_organization_members(org), score_in_organization_members(org)
    # → V2::Organization: members, add_member(customer, score), remove_member(customer),
    #                     add_members(customers), members_with_permission(min_permission)
    participates_in V2::Organization, :members, score: :joined_at

    # Participation: Score based on when added
    # → Customer: in_team_members?(team), add_to_team_members(team, score),
    #             remove_from_team_members(team), score_in_team_members(team)
    # → V2::Team: members, add_member(customer, score), remove_member(customer),
    #             add_members(customers), members_with_permission(min_permission)
    participates_in V2::Team, :members

    # Unique Index: Fast lookups scoped by organization
    # → Customer: add_to_organization_email_index(org), remove_from_organization_email_index(org),
    #             update_in_organization_email_index(org, old_email)
    # → V2::Organization: find_by_email(email), find_all_by_email([emails]), email_index
    unique_index :email, :email_index, within: V2::Organization

    # → Customer: add_to_organization_objid_index(org), remove_from_organization_objid_index(org),
    #             update_in_organization_objid_index(org, old_objid)
    # → V2::Organization: find_by_objid(objid), find_all_by_objid([objids]), objid_index
    unique_index :objid, :objid_index, within: V2::Organization

    # → Customer: add_to_organization_extid_index(org), remove_from_organization_extid_index(org),
    #             update_in_organization_extid_index(org, old_extid)
    # → V2::Organization: find_by_extid(extid), find_all_by_extid([extids]), extid_index
    unique_index :extid, :extid_index, within: V2::Organization

    # Unique Index: Fast lookups scoped by team
    # → Customer: add_to_team_email_index(team), remove_from_team_email_index(team),
    #             update_in_team_email_index(team, old_email)
    # → V2::Team: find_by_email(email), find_all_by_email([emails]), email_index
    unique_index :email, :email_index, within: V2::Team

    # → Customer: add_to_team_objid_index(team), remove_from_team_objid_index(team),
    #             update_in_team_objid_index(team, old_objid)
    # → V2::Team: find_by_objid(objid), find_all_by_objid([objids]), objid_index
    unique_index :objid, :objid_index, within: V2::Team

    # Unique Index: Global system-wide lookups (class-level)
    # → Customer class: Customer.find_by_email(email), Customer.find_all_by_email([emails]),
    #                   Customer.customer_email_index
    # → Customer instance: add_to_class_customer_email_index,
    #                      remove_from_class_customer_email_index,
    #                      update_in_class_customer_email_index(old_email)
    unique_index :email, :customer_email_index

    # → Customer class: Customer.find_by_objid(objid), Customer.find_all_by_objid([objids]),
    #                   Customer.customer_objid_index
    # → Customer instance: add_to_class_customer_objid_index,
    #                      remove_from_class_customer_objid_index,
    #                      update_in_class_customer_objid_index(old_objid)
    unique_index :objid, :customer_objid_index

    # → Customer class: Customer.find_by_extid(extid), Customer.find_all_by_extid([extids]),
    #                   Customer.customer_extid_index
    # → Customer instance: add_to_class_customer_extid_index,
    #                      remove_from_class_customer_extid_index,
    #                      update_in_class_customer_extid_index(old_extid)
    unique_index :extid, :customer_extid_index

    # # Track with permission encoding in score
    # # → Customer: in_organization_members?(org), add_to_organization_members(org, score), remove_from_organization_members(org), score_in_organization_members(org)
    # # → V2::Organization: members, add_member(customer, score), remove_member(customer), add_members(customers), members_with_permission(min_permission)
    # participates_in V2::Organization, :members, score: :joined_at

    # # score is based on when added
    # # → Customer: in_team_members?(team), add_to_team_members(team, score), remove_from_team_members(team), score_in_team_members(team)
    # # → V2::Team: members, add_member(customer, score), remove_member(customer), add_members(customers), members_with_permission(min_permission)
    # participates_in V2::Team, :members

    # # Fast lookups - scoped by organization/team
    # # → Customer: add_to_organization_email_index(org), remove_from_organization_email_index(org), update_in_organization_email_index(org, old_email)
    # # → V2::Organization: find_by_email(email), find_all_by_email([emails]), email_index_for(email_value)
    # indexed_by :email, :email_index, target: V2::Organization

    # # → Customer: add_to_organization_objid_index(org), remove_from_organization_objid_index(org), update_in_organization_objid_index(org, old_objid)
    # # → V2::Organization: find_by_objid(objid), find_all_by_objid([objids]), objid_index_for(objid_value)
    # indexed_by :objid, :objid_index, target: V2::Organization

    # # → Customer: add_to_organization_extid_index(org), remove_from_organization_extid_index(org), update_in_organization_extid_index(org, old_extid)
    # # → V2::Organization: find_by_extid(extid), find_all_by_extid([extids]), extid_index_for(extid_value)
    # indexed_by :extid, :extid_index, target: V2::Organization

    # # → Customer: add_to_team_email_index(team), remove_from_team_email_index(team), update_in_team_email_index(team, old_email)
    # # → V2::Team: find_by_email(email), find_all_by_email([emails]), email_index_for(email_value)
    # indexed_by :email, :email_index, target: V2::Team

    # # → Customer: add_to_team_objid_index(team), remove_from_team_objid_index(team), update_in_team_objid_index(team, old_objid)
    # # → V2::Team: find_by_objid(objid), find_all_by_objid([objids]), objid_index_for(objid_value)
    # indexed_by :objid, :objid_index, target: V2::Team

    # # Global system-wide lookups
    # # → Customer class: Customer.find_by_email(email), Customer.find_all_by_email([emails]), Customer.customer_email_index
    # # → Customer instance: add_to_class_customer_email_index, remove_from_class_customer_email_index, update_in_class_customer_email_index(old_email)
    # class_indexed_by :email, :customer_email_index

    # # → Customer class: Customer.find_by_objid(objid), Customer.find_all_by_objid([objids]), Customer.customer_objid_index
    # # → Customer instance: add_to_class_customer_objid_index, remove_from_class_customer_objid_index, update_in_class_customer_objid_index(old_objid)
    # class_indexed_by :objid, :customer_objid_index

    # # → Customer class: Customer.find_by_extid(extid), Customer.find_all_by_extid([extids]), Customer.customer_extid_index
    # # → Customer instance: add_to_class_customer_extid_index, remove_from_class_customer_extid_index, update_in_class_customer_extid_index(old_extid)
    # class_indexed_by :extid, :customer_extid_index

    # attempt1 - 17:51
    #
    # # Track with permission encoding in score
    # participates_in V2::Organization, :members, score: :joined_at  # → add_organization_membership, remove_organization_membership, organization_memberships, clear_organization_memberships
    # participates_in V2::Team, :members # score is based on when added  # → add_team_membership, remove_team_membership, team_memberships, clear_team_memberships

    # # Fast lookups - scoped by organization/team
    # indexed_by :email, :email_index, target: V2::Organization      # → email_index (scoped method), find_by_email_in_organization
    # indexed_by :objid, :objid_index, target: V2::Organization      # → objid_index (scoped method), find_by_objid_in_organization
    # indexed_by :extid, :extid_index, target: V2::Organization      # → extid_index (scoped method), find_by_extid_in_organization

    # indexed_by :email, :email_index, target: V2::Team             # → email_index (scoped method), find_by_email_in_team
    # indexed_by :objid, :objid_index, target: V2::Team             # → objid_index (scoped method), find_by_objid_in_team

    # # Global system-wide lookups
    # class_indexed_by :email, :customer_email_index                # → Customer.customer_email_index (class method), Customer.find_by_customer_email_index
    # class_indexed_by :objid, :customer_objid_index                # → Customer.customer_objid_index (class method), Customer.find_by_customer_objid_index
    # class_indexed_by :extid, :customer_extid_index                # → Customer.customer_extid_index (class method), Customer.find_by_customer_extid_index

    # # The generated methods follow these patterns:
    # #
    # # Participation methods:
    # # - add_{target_class}_{relation_name}(target_object)
    # # - remove_{target_class}_{relation_name}(target_object)
    # # - {target_class}_{relation_name} (returns collection)
    # # - clear_{target_class}_{relation_name}
    # #
    # # Scoped indexes:
    # # - {field_name}_index (returns scoped index for queries)
    # # - find_by_{field_name}_in_{target_class}(value, scope_object)
    # #
    # # Class-level indexes:
    # # - ClassName.{index_name} (class method returning index)
    # # - ClassName.find_by_{index_name}(value)


    field :custid
    field :email

    field :locale
    field :planid

    field :last_login

    def init
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
      role.to_s.eql?('anonymous')
    end

    def obscure_email
      return 'anon' if anonymous?

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
