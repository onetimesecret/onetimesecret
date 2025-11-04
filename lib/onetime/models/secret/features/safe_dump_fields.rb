# lib/onetime/models/secret/features/safe_dump_fields.rb

module Onetime::Secret::Features
  module SafeDumpFields
    Onetime::Secret.add_feature self, :safe_dump_fields

    def self.included(base)
      # Lambda to handle counter fields that may be nil/empty - returns '0'
      # if empty, otherwise the string value
      counter_field_handler = lambda { |cust, field_name|
        value = cust.send(field_name).to_s
        value.empty? ? '0' : value
      }

      # Enable the Familia SafeDump feature
      base.feature :safe_dump

      # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
      # with hot reloading in dev mode will not work. You will need to restart the
      # server to see the changes.

      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :key, ->(obj) { obj.identifier }
      base.safe_dump_field :shortid, ->(obj) { obj.shortid }
      base.safe_dump_field :state
      base.safe_dump_field :secret_ttl, ->(m) { m.lifespan }
      base.safe_dump_field :lifespan
      base.safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
      base.safe_dump_field :verification, ->(m) { m.verification? }
      base.safe_dump_field :is_truncated, ->(m) { m.truncated? }
      base.safe_dump_field :created
      base.safe_dump_field :updated

    end
  end
end
