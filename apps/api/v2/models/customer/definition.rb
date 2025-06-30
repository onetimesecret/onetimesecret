# apps/api/v2/models/customer/class_methods.rb

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

    include Gibbler::Complex

    @global = nil

    feature :safe_dump
    feature :expiration

    prefix :customer

    class_sorted_set :values, key: 'onetime:customer'
    class_sorted_set :object_ids

    class_hashkey :email_to_objid # While migrating we'll need to maintain
    class_hashkey :objid_to_email # indexes in both directions.

    class_hashkey :domains, key: 'onetime:customers:domain'

    sorted_set :custom_domains, suffix: 'custom_domain'
    sorted_set :metadata

    hashkey :feature_flags # e.g. isBetaEnabled

    # Used to track the current and most recently created password reset secret.
    string :reset_secret, ttl: 24.hours

    identifier :custid

    field :custid
    field :email

    field :objid # uuid v7
    field :extid # sha256(objid)

    field :role # customer, colonel
    field :user_type # 'anonymous', 'authenticated', 'standard', 'enhanced'
    field :api_version # v2

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
  end
end
