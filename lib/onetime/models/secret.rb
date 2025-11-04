# lib/onetime/models/secret.rb

require 'familia/verifiable_identifier'

require_relative 'secret/features'

module Onetime
  class Secret < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    feature :object_identifier,
      generator: proc { Familia::VerifiableIdentifier.generate_verifiable_id }
    feature :safe_dump_fields
    feature :expiration
    feature :relationships
    feature :required_fields
    feature :encrypted_fields
    feature :transient_fields
    feature :secret_state_management
    feature :legacy_encrypted_fields
    feature :deprecated_fields

    default_expiration 7.days # default only, can be overridden at create time
    prefix :secret

    identifier_field :objid

    field :state
    field :lifespan
    field :metadata_identifier

    encrypted_field :ciphertext
    transient_field :ciphertext_passphrase
    transient_field :ciphertext_domain

    def init
      self.state ||= 'new'
    end

    def shortid
      identifier.slice(0, 6)
    end

    def age
      @age ||= Familia.now.to_i - updated
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
      Onetime::Metadata.load metadata_identifier
    end
  end
end
