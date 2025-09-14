# lib/onetime/models/customer/features/safe_dump_fields.rb

module Onetime::Customer::Features
  module SafeDump

    Onetime::Customer.add_feature self, :safe_dump_fields

    def self.included(base)
      # Lambda to handle counter fields that may be nil/empty - returns '0'
      # if empty, otherwise the string value
      counter_field_handler = lambda { |cust, field_name|
        value = cust.send(field_name).to_s
        value.empty? ? '0' : value
      }

      base.feature :safe_dump

      # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
      # with hot reloading in dev mode will not work. You will need to restart the
      # server to see the changes.
      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :custid
      base.safe_dump_field :email
      base.safe_dump_field :role
      base.safe_dump_field :verified
      base.safe_dump_field :last_login
      base.safe_dump_field :locale
      base.safe_dump_field :updated
      base.safe_dump_field :created
      base.safe_dump_field :stripe_customer_id
      base.safe_dump_field :stripe_subscription_id
      base.safe_dump_field :stripe_checkout_email
      base.safe_dump_field :planid

      # NOTE: The secrets_created incrementer is null until the first secret
      # is created. See ConcealSecret for where the incrementer is called. This
      # actually applies to all fields used as incrementers. We use the
      # `counter_field_handler` lambda to return 0 if the field is nil or empty.
      base.safe_dump_field :secrets_created, ->(cust) { counter_field_handler.call(cust, :secrets_created) }
      base.safe_dump_field :secrets_burned, ->(cust) { counter_field_handler.call(cust, :secrets_burned) }
      base.safe_dump_field :secrets_shared, ->(cust) { counter_field_handler.call(cust, :secrets_shared) }
      base.safe_dump_field :emails_sent, ->(cust) { counter_field_handler.call(cust, :emails_sent) }

      # We use the hash syntax here since `:active?` is not a valid symbol.
      base.safe_dump_field :active, ->(cust) { cust.active? }
    end

  end
end
