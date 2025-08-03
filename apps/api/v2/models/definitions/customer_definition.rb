# apps/api/v2/models/definitions/customer_definition.rb

require 'rack/utils'

require_relative '../mixins/passphrase'

module V2
  class Customer < Familia::Horreum

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

    # Lambda to handle counter fields that may be nil/empty - returns '0'
    # if empty, otherwise the string value
    counter_field_handler = lambda { |cust, field_name|
      value = cust.send(field_name).to_s
      value.empty? ? '0' : value
    }

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
      # is created. See ConcealSecret for where the incrementer is called. This
      # actually applies to all fields used as incrementers. We use the
      # `counter_field_handler` lambda to return 0 if the field is nil or empty.
      #
      {:secrets_created => ->(cust) { counter_field_handler.call(cust, :secrets_created) } },
      {:secrets_burned => ->(cust) { counter_field_handler.call(cust, :secrets_burned) } },
      {:secrets_shared => ->(cust) { counter_field_handler.call(cust, :secrets_shared) } },
      {:emails_sent => ->(cust) { counter_field_handler.call(cust, :emails_sent) } },

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
      self.secrets_burned  ||= 0
      self.secrets_shared  ||= 0
      self.emails_sent     ||= 0
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
