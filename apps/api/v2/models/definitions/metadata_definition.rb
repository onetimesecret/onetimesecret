# apps/api/v2/models/definitions/metadata_definition.rb

module V2
  class Metadata < Familia::Horreum
    feature :safe_dump
    feature :expiration

    ttl 14.days
    prefix :metadata

    identifier :generate_id

    field :custid
    field :state
    field :secret_key
    field :secret_shortkey
    field :secret_ttl
    field :lifespan
    field :share_domain
    field :passphrase
    field :viewed
    field :received
    field :shared
    field :burned
    field :created
    field :updated
    # NOTE: There is no `expired` timestamp field since we can calculate
    # that based on the `secret_ttl` and the `created` timestamp. See
    # the secret_expired? and expiration methods.
    field :recipients
    field :truncate # boolean

    # NOTE: this field is a nullop. It's only populated if a value was entered
    # into a hidden field which is something a regular person would not do.
    field :token

    # NOTE: Safe dump fields are loaded once at start time so they're
    # immune to hot reloads.
    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :key,
      :custid,
      :state,
      :secret_shortkey,
      :secret_ttl,
      { metadata_ttl: ->(m) { m.lifespan } },
      :lifespan,
      :share_domain,
      :created,
      :updated,
      :shared,
      :received,
      :burned,
      :viewed,
      :recipients,

      { shortkey: ->(m) { m.key.slice(0, 8) } },
      { show_recipients: ->(m) { !m.recipients.to_s.empty? } },

      { is_viewed: ->(m) { m.state?(:viewed) } },
      { is_received: ->(m) { m.state?(:received) } },
      { is_burned: ->(m) { m.state?(:burned) } },
      { is_expired: ->(m) { m.state?(:expired) } },
      { is_orphaned: ->(m) { m.state?(:orphaned) } },
      { is_destroyed: lambda { |m|
        m.state?(:received) || m.state?(:burned) || m.state?(:expired) || m.state?(:orphaned)
      } },

      # We use the hash syntax here since `:truncated?` is not a valid symbol.
      { is_truncated: ->(m) { m.truncated? } },

      { has_passphrase: ->(m) { m.has_passphrase? } },
    ]

    def init
      self.state ||= 'new'
    end
  end
end
