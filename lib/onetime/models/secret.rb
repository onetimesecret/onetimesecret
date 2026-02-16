# lib/onetime/models/secret.rb
#
# frozen_string_literal: true

require 'familia/verifiable_identifier'

module Onetime
  class Secret < Familia::Horreum
    include Familia::Features::Autoloader

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

    # Migration features - REMOVE after v1→v2 migration complete
    feature :with_migration_fields
    feature :secret_migration_fields

    default_expiration 7.days # default only, can be overridden at create time
    prefix :secret

    identifier_field :objid

    field :state
    field :lifespan
    field :receipt_identifier
    field :receipt_shortid
    field :owner_id

    encrypted_field :ciphertext
    transient_field :ciphertext_passphrase
    transient_field :ciphertext_domain

    def init
      self.state ||= 'new'
    end

    def shortid
      identifier.slice(0, 8)
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

    def load_owner
      Onetime::Customer.load owner_id
    end

    def owner?(fobj)
      fobj && (fobj.objid == owner_id)
    end

    def older_than?(seconds)
      age > seconds
    end

    def valid?
      exists? && (!ciphertext.to_s.empty? || !value.to_s.empty?)
    end

    # Transparently decrypt the secret payload regardless of storage format.
    # Routes on `value_encryption`: present means v1 (legacy OpenSSL via
    # LegacyEncryptedFields#decrypted_value), absent means v2 (Familia
    # encrypted_field with self-describing JSON envelope).
    def decrypted_secret_value(passphrase_input: nil)
      if !ciphertext.to_s.empty?
        ciphertext.reveal { it }
      elsif !value_encryption.to_s.empty?
        @passphrase_temp = passphrase_input.to_s.empty? ? nil : passphrase_input
        decrypted_value
      end
    end

    def truncated?
      truncated.to_s == 'true'
    end

    def verification?
      verification.to_s == 'true'
    end

    def load_receipt
      Onetime::Receipt.load receipt_identifier
    end
  end
end
