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

    # Presentation hint for the reveal page: how the recipient's client should
    # display the decrypted value. Stamped once at creation
    # (Receipt.spawn_pair, from the conceal request) and never inferred from
    # the content. One of DISPLAY_TYPES; nil/empty (every record created before
    # the field existed) reads as DEFAULT_DISPLAY_TYPE via
    # #display_type_or_default. Not a security control: the client must
    # sanitize whatever a type renders. See docs/specs/secret-display-type.md.
    field :display_type

    encrypted_field :ciphertext
    transient_field :ciphertext_passphrase
    transient_field :ciphertext_domain

    # Closed value space for :display_type. Kept as strings to match the
    # :state / :kind convention. Extend here (e.g. 'httplink' for a "you are
    # about to open an external link" interstitial) without a schema change;
    # a client that does not know a value falls back to plain text.
    DISPLAY_TYPES        = %w[text markdown].freeze
    DEFAULT_DISPLAY_TYPE = 'text'

    def init
      self.state ||= 'new'
    end

    # Whether the given value names a known display type.
    #
    # @param value [String, Symbol, nil]
    # @return [Boolean]
    def self.valid_display_type?(value)
      DISPLAY_TYPES.include?(value.to_s)
    end

    # The stored display type, or the plain-text default when the field is
    # unset (pre-field records) or holds a value this build does not know
    # (a downgrade after a newer type shipped). Falls back to text rather
    # than raising: display is a hint, and the value is still deliverable.
    #
    # @return [String] one of DISPLAY_TYPES
    def display_type_or_default
      value = display_type.to_s
      self.class.valid_display_type?(value) ? value : DEFAULT_DISPLAY_TYPE
    end

    def markdown?
      display_type_or_default == 'markdown'
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
      # Capture the identity BEFORE super — destroy! clears the record, and the
      # owner index needs the member name to remove.
      oid    = objid
      owner  = owner_id
      result = super
      Onetime::Customer.decrement_secrets_active(owner, secret_id: oid)
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
