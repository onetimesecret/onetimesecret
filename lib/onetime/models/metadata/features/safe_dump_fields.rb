# lib/onetime/models/metadata/features/safe_dump_fields.rb

module Onetime::Metadata::Features
  module SafeDumpFields
    # Register our custom SafeDump feature with a unique
    Onetime::Metadata.add_feature self, :safe_dump_fields

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
      base.safe_dump_field :custid
      base.safe_dump_field :owner_id
      base.safe_dump_field :state
      base.safe_dump_field :secret_shortid
      base.safe_dump_field :secret_ttl, ->(m) { m.secret_ttl || -1 }
      base.safe_dump_field :metadata_ttl, ->(m) { m.lifespan }
      base.safe_dump_field :lifespan
      base.safe_dump_field :share_domain
      base.safe_dump_field :created
      base.safe_dump_field :updated
      base.safe_dump_field :shared
      base.safe_dump_field :received
      base.safe_dump_field :burned
      base.safe_dump_field :viewed
      base.safe_dump_field :recipients
      base.safe_dump_field :shortid, ->(m) { m.identifier.slice(0, 8) }
      base.safe_dump_field :show_recipients, ->(m) { !m.recipients.to_s.empty? }
      base.safe_dump_field :is_viewed, ->(m) { m.state?(:viewed) }
      base.safe_dump_field :is_received, ->(m) { m.state?(:received) }
      base.safe_dump_field :is_burned, ->(m) { m.state?(:burned) }
      base.safe_dump_field :is_expired, ->(m) { m.state?(:expired) }
      base.safe_dump_field :is_orphaned, ->(m) { m.state?(:orphaned) }
      base.safe_dump_field :is_destroyed, lambda { |m|
        m.state?(:received) || m.state?(:burned) || m.state?(:expired) || m.state?(:orphaned)
      }
      # We use the hash syntax here since `:truncated?` is not a valid symbol.
      # base.safe_dump_field :is_truncated, ->(m) { m.truncated? }
      base.safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
    end
  end
end
