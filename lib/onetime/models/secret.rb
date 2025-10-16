# lib/onetime/models/secret.rb

require_relative 'secret/features'

module Onetime
  class Secret < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    feature :safe_dump
    feature :expiration
    feature :relationships
    feature :object_identifier
    feature :required_fields
    feature :secret_encryption
    feature :secret_state_management
    feature :secret_customer_relations
    feature :legacy_encrypted_fields
    feature :deprecated_fields

    default_expiration 7.days # default only, can be overridden at create time
    prefix :secret

    identifier_field :key

    field :custid
    field :state
    field :value
    field :key
    field :metadata_key
    field :value_encryption
    field :lifespan
    field :share_domain
    field :verification
    field :truncated # boolean

    counter :view_count, default_expiration: 14.days # out lives the secret itself

    safe_dump_field :identifier, ->(obj) { obj.identifier }
    safe_dump_field :key
    safe_dump_field :state
    safe_dump_field :secret_ttl, ->(m) { m.lifespan }
    safe_dump_field :lifespan
    safe_dump_field :shortkey, ->(m) { m.key.slice(0, 8) }
    safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
    safe_dump_field :verification, ->(m) { m.verification? }
    safe_dump_field :is_truncated, ->(m) { m.truncated? }
    safe_dump_field :created
    safe_dump_field :updated

    def init
      self.state ||= 'new'
      self.key   ||= self.class.generate_id # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def shortkey
      key.slice(0, 6)
    end

    def age
      @age ||= Familia.now.to_i - updated
      @age
    end

    def expiration
      # Unix timestamp of when this secret will expire. Based on
      # the secret's TTL (lifespan) and the created time of the secret.
      lifespan.to_i + created.to_i if lifespan
    end

    def natural_duration
      # Colloquial representation of the TTL. e.g. "1 day"
      OT::Utils::TimeUtils.natural_duration lifespan
    end

    def older_than?(seconds)
      age > seconds
    end

    def valid?
      exists? && !value.to_s.empty?
    end

    def truncated?
      truncated.to_s == 'true'
    end

    def verification?
      verification.to_s == 'true'
    end

    def load_metadata
      Onetime::Metadata.load metadata_key
    end
  end
end
