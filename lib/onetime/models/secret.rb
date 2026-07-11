# lib/onetime/models/secret.rb
#
# frozen_string_literal: true

require 'familia/verifiable_identifier'

module Onetime
  class Secret < Familia::Horreum
    include Familia::Features::Autoloader

    SCHEMA = 'models/secret'

    using Familia::Refinements::TimeLiterals

    feature :object_identifier,
      generator: proc { Familia::VerifiableIdentifier.generate_verifiable_id }
    feature :safe_dump_fields
    feature :expiration
    feature :relationships
    feature :required_fields
    feature :encrypted_fields
    feature :transient_fields
    feature :state_cas
    feature :secret_state_management
    feature :passphrase_hashing
    feature :deprecated_fields
    feature :housekeeping

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

    # Destroy the record and keep the owner's live-secret counter in step.
    # destroy! is the single application-code chokepoint through which a secret
    # disappears early — reveal (consume_after_reveal!), burn (burned!), and
    # the colonel delete all funnel through it — mirroring the increment at the
    # creation chokepoint (Receipt.spawn_pair → increment_secrets_active).
    # TTL expiry still runs no application code, so the nightly
    # SecretCountReconcileJob remains the correctness mechanism for that path.
    # The helper is fail-open and clamps at zero; see counter_fields.rb (#60).
    def destroy!
      result = super
      Onetime::Customer.decrement_secrets_active(owner_id)
      result
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

    def anonymous?
      owner_id.to_s == 'anon'
    end

    def owner?(fobj)
      !!(fobj && !anonymous? && (fobj.objid == owner_id))
    end

    def older_than?(seconds)
      age > seconds
    end

    def valid?
      exists? && !ciphertext.to_s.empty?
    end

    def decrypted_secret_value(**)
      return if ciphertext.to_s.empty?

      ciphertext.reveal { it }&.force_encoding('utf-8')
    end

    def can_decrypt?
      !ciphertext.to_s.empty? && passphrase.to_s.empty?
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
