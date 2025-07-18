# apps/api/v2/models/customer/definition.rb

require_relative '../mixins/passphrase'
require_relative '../mixins/maintenance'

module V2
  # Customer Model - Class Methods
  #
  class Customer < Familia::Horreum
    # Mixin Placement for Field Order Control
    #
    # We include mixins at the end of the model definition (e.g. if in the same
    # file, then at the very end of the class before it closes) so that if they
    # add new fields or relationships, the order of fields is maintained.
    #
    # In Familia::Horreum subclasses (like this Customer class), fields are
    # processed in the order they are defined. When creating a new instance
    # with Session.new, any provided positional arguments correspond to
    # these fields in the same order.
    #
    # By including Passphrase last, we ensure that:
    # 1. Its additional fields appear at the end of the field list.
    # 2. These fields don't unexpectedly consume positional arguments
    # in Session.new.
    #
    # e.g. `Customer.new('my@example.com')`. If we included thePassphrase
    # module at the top, instead of populating the custid field (as the
    # first field defined in this file), this email address would get
    # written to the (automatically inserted) passphrase field.
    #
    include V2::Mixins::Passphrase
    include V2::Mixins::ModelMaintenance

    @global = nil

    feature :core_object
    feature :safe_dump
    feature :expiration

    prefix :customer

    class_sorted_set :values, key: 'onetime:customer'

    class_hashkey :email_to_objid # While migrating we'll need to maintain
    class_hashkey :objid_to_email # indexes in both directions.

    class_hashkey :domains, key: 'onetime:customers:domain'

    sorted_set :custom_domains, suffix: 'custom_domain'
    sorted_set :metadata

    hashkey :feature_flags # e.g. isBetaEnabled

    # Used to track the current and most recently created password reset secret.
    string :reset_secret, ttl: 24.hours

    field :custid
    field :email

    field :role # customer, colonel
    field :user_type # 'anonymous', 'authenticated', 'standard', 'enhanced'

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
      { identifier: ->(obj) { obj.identifier } },
      :custid,
      :email,
      :objid,
      :extid,

      :api_version,
      :role,
      :user_type,

      :verified,
      :last_login,
      :locale,
      :updated,
      :created,

      :stripe_customer_id,
      :stripe_subscription_id,
      :stripe_checkout_email,
      :planid,

      # Removed for #1508 on 2025-06-24. Use user_type for functional logic.
      #
      # { plan: ->(cust) { cust.load_plan } },

      # NOTE: The secrets_created incrementer is null until the first secret
      # is created. See ConcealSecret for where the incrementer is called.
      #
      { secrets_created: ->(cust) { cust.secrets_created.to_s || 0 } },
      { secrets_burned: ->(cust) { cust.secrets_burned.to_s || 0 } },
      { secrets_shared: ->(cust) { cust.secrets_shared.to_s || 0 } },
      { emails_sent: ->(cust) { cust.emails_sent.to_s || 0 } },

      # We use the hash syntax here since `:active?` is not a valid symbol.
      { active: ->(cust) { cust.active? } },
    ].freeze

    def init
      super if defined?(super)

      # Default to anonymous state. That way we're always explicitly
      # setting the role when it needs to be set.
      #
      # Previously we used custid=anon and all it would do is prevent
      # the record from being saved.
      self.user_type   ||= 'anonymous'
      self.role        ||= 'customer'

      # Set email only for non-anonymous users
      if !anonymous? && email.to_s.empty? && !custid.to_s.empty?
        self.email = custid
      end

      # Set custid only for non-anonymous users
      if !anonymous? && custid.to_s.empty? && !email.to_s.empty?
        self.custid = email
      end

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
      self.secrets_burned  ||= 0
      self.secrets_shared  ||= 0
      self.emails_sent     ||= 0
    end
  end
end
