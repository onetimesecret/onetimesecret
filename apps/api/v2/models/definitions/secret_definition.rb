# apps/api/v2/models/definitions/secret_definition.rb

module V2
  class Secret < Familia::Horreum
    feature :safe_dump
    feature :expiration

    ttl 7.days # default only, can be overridden at create time
    prefix :secret

    identifier_field :generate_id

    field :custid
    field :state
    field :value
    field :metadata_key
    field :value_encryption
    field :lifespan
    field :share_domain
    field :verification
    field :updated
    field :created
    field :truncated # boolean
    field :maxviews # always 1 (here for backwards compat)

    # The key field is added automatically by Familia::Horreum and works
    # just fine except for rspec mocks that use `instance_double`. Mocking
    # a secret that includes a value for `key` will trigger an error (since
    # instance_double considers the real class). See spec_helpers.rb
    field :key

    counter :view_count, default_expiration: 14.days # out lives the secret itself

    # NOTE: this field is a nullop. It's only populated if a value was entered
    # into a hidden field which is something a regular person would not do.
    field :token

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :key,
      :state,
      { secret_ttl: ->(m) { m.lifespan } },
      :lifespan,
      { shortkey: ->(m) { m.key.slice(0, 8) } },
      { has_passphrase: ->(m) { m.has_passphrase? } },
      { verification: ->(m) { m.verification? } },
      { is_truncated: ->(m) { m.truncated? } },
      :created,
      :updated,
    ]

    def init
      self.state ||= 'new'
    end
  end
end
