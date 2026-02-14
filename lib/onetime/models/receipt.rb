# lib/onetime/models/receipt.rb
#
# frozen_string_literal: true

module Onetime
  class Receipt < Familia::Horreum
    include Familia::Features::Autoloader
    include Onetime::LoggerMethods

    using Familia::Refinements::TimeLiterals

    feature :object_identifier,
      generator: proc { Familia::VerifiableIdentifier.generate_verifiable_id }
    feature :safe_dump_fields
    feature :expiration
    feature :relationships
    feature :required_fields
    feature :deprecated_fields

    # Migration features - REMOVE after v1→v2 migration complete
    feature :with_migration_fields
    feature :receipt_migration_fields

    default_expiration 14.days # by default 2x Secret.default_expiration
    prefix :receipt

    identifier_field :objid

    field :owner_id
    field :state
    field :secret_identifier
    field :secret_shortid
    field :secret_ttl
    field :lifespan
    field :share_domain
    field :has_passphrase

    # Organization and domain tracking for scoped receipt queries
    field :org_id      # Organization objid (current context when created)
    field :domain_id   # CustomDomain objid (when using registered custom domain)

    # Familia v2 relationships - enables org.receipts and custom_domain.receipts queries
    # These auto-generate sorted_set collections on the target models
    # NOTE: Uses full class names (Onetime::X) to ensure Familia can resolve the target class
    participates_in Onetime::Organization, :receipts, score: :created
    participates_in Onetime::CustomDomain, :receipts, score: :created

    # NOTE: There is no `expired` timestamp field since we can calculate
    # that based on the `secret_ttl` and the `created` timestamp. See
    # the secret_expired? and expiration methods.
    field :recipients
    field :memo  # Optional memo/subject for incoming secrets

    # Class-level collections for expiration warning feature
    # Sorted set: score = expiration timestamp, member = receipt identifier
    class_sorted_set :expiration_timeline
    # Set for tracking which secrets have already received warnings
    class_set :warnings_sent

    def init
      self.state ||= 'new'
    end

    # Clean up class-level collections before destroying the object.
    # Familia's base destroy! handles the main key and related fields,
    # but class-level sorted sets and sets need explicit cleanup.
    def destroy!
      # Remove from organization participations before Familia cleanup
      organization_instances.each do |o|
        remove_from_organization_receipts(o)
      end

      # Remove from custom domain participations before Familia cleanup
      custom_domain_instances.each do |domain|
        remove_from_custom_domain_receipts(domain)
      end

      # Call Familia's built-in destroy first. If it fails, we won't proceed
      # with cleaning up the class-level collections, leaving the system in
      # a more consistent state. Handles: main object key deletion, related
      # fields cleanup, instances collection removal, objid/extid lookup cleanup.
      super

      # If super succeeds, clean up our custom class-level collections
      # Remove from expiration timeline tracking (sorted set)
      self.class.expiration_timeline.remove_element(identifier)

      # Remove from warnings_sent tracking (set)
      self.class.warnings_sent.remove_element(identifier)
    end

    def age
      @age ||= Familia.now.to_i - updated
      @age
    end

    def receipt_ttl
      # Stay alive for twice as long as the secret so that we can
      # provide the receipt page even after the secret is gone.
      (secret_ttl.to_i * 2) if secret_ttl.to_i > 0
    end
    alias expiration_in_seconds receipt_ttl

    def expiration
      # Unix timestamp of when the receipt will expire. Based on
      # the secret_ttl and the created time of the receipt.
      receipt_ttl.to_i + created.to_i if receipt_ttl
    end

    def natural_duration
      # Colloquial representation of the TTL. e.g. "1 day"
      OT::Utils::TimeUtils.natural_duration receipt_ttl
    end

    def secret_expiration
      # Unix timestamp of when the secret will expire. Based on
      # the secret_ttl and the created time of the receipt
      # (which should be identical. See Secret.spawn_pair).
      secret_ttl.to_i + created.to_i if secret_ttl
    end

    def secret_natural_duration
      # Colloquial representation of the TTL. e.g. "1 day"
      OT::Utils::TimeUtils.natural_duration secret_ttl.to_i if secret_ttl
    end

    def secret_expired?
      Familia.now.to_i >= (secret_expiration || 0)
    end

    def older_than?(seconds)
      age > seconds
    end

    def shortid
      identifier.slice(0, 8)
    end

    def anonymous?
      owner_id.to_s == 'anon'
    end

    def owner?(cust)
      !anonymous? && (cust.is_a?(Onetime::Customer) ? cust.custid : cust).to_s == owner_id.to_s
    end

    def valid?
      exists?
    end

    def has_passphrase?
      !has_passphrase.nil? && has_passphrase
    end

    def load_owner
      Onetime::Customer.load owner_id
    end

    def owner?(fobj)
      fobj && (fobj.objid == owner_id)
    end

    def load_secret
      Onetime::Secret.load secret_identifier
    end

    # Register this receipt for expiration notifications
    # Called during secret creation to track secrets that should receive warnings
    # @return [Boolean] true if registered, false if skipped
    def register_for_expiration_notifications
      return false unless secret_expiration
      return false if secret_ttl.to_i < self.class.min_warning_ttl

      self.class.expiration_timeline.add(identifier, secret_expiration.to_f)
      true
    end

    class << self
      def generate_id
        Familia.generate_id
      end

      def count
        instances.count # e.g. zcard dbkey
      end

      # Creates a linked Secret and Receipt pair for secure content storage.
      #
      # SECURITY CONTRACT: Callers must validate domain and passphrase before
      # calling this method, as both are used as cryptographic inputs:
      #
      # - domain: Used as Additional Authenticated Data (AAD) for encryption.
      #   API callers validate via: process_share_domain (format validation),
      #   validate_domain_access (DB lookup + existence check), and
      #   validate_domain_permissions (ownership/access rules). Attackers
      #   cannot bind secrets to arbitrary AAD values.
      #
      # - passphrase: Used for secret access control (encrypted before storage).
      #   API callers validate via: validate_passphrase (min/max length) and
      #   validate_passphrase_complexity (when enforce_complexity enabled).
      #
      # See: apps/api/v2/logic/secrets/base_secret_action.rb for validation.
      #
      def spawn_pair(owner_id, lifespan, content, passphrase: nil, domain: nil)
        secret  = Onetime::Secret.new(owner_id: owner_id)
        receipt = Onetime::Receipt.new(owner_id: owner_id)

        receipt.secret_identifier  = secret.objid
        receipt.default_expiration = lifespan * 2
        receipt.save

        secret.default_expiration = lifespan
        secret.lifespan           = lifespan
        secret.receipt_identifier = receipt.objid

        # NOTE: Transient fields that are used for aad protection (like
        # ciphertext_domain) need to be populated before encrypting the
        # content.
        secret.ciphertext_domain = domain
        secret.share_domain      = domain
        secret.ciphertext        = content

        # Set the passphrase via the special update method that ensures it
        # is encrypted before its saved. We could override the field setter,
        # but prefer to be explicit about it.
        unless passphrase.nil?
          secret.update_passphrase passphrase
          receipt.has_passphrase = true
        end

        secret.save

        receipt.secret_shortid = secret.shortid
        receipt.secret_ttl     = lifespan
        receipt.lifespan       = lifespan
        receipt.share_domain   = domain
        receipt.save

        # Register for expiration warnings if feature is enabled and TTL is long enough
        receipt.register_for_expiration_notifications

        [receipt, secret]
      end

      # Minimum TTL (in seconds) for secrets to be eligible for expiration warnings
      # Secrets with shorter TTL won't receive warnings to avoid spam
      # @return [Integer] TTL in seconds
      def min_warning_ttl
        hours = OT.conf.dig('jobs', 'expiration_warnings', 'min_ttl_hours').to_i
        hours = 48 if hours <= 0
        hours * 3600
      end

      # Find receipt IDs for secrets expiring within the given time window
      # @param seconds [Integer] Time window in seconds from now
      # @return [Array<String>] Receipt identifiers
      def expiring_within(seconds)
        now = Familia.now.to_f
        expiration_timeline.rangebyscore(now, now + seconds)
      end

      # Check if a warning has already been sent for this receipt
      # @param receipt_id [String] Receipt identifier
      # @return [Boolean]
      def warning_sent?(receipt_id)
        warnings_sent.member?(receipt_id)
      end

      # Mark that a warning has been sent for this receipt
      # @param receipt_id [String] Receipt identifier
      # @return [Boolean]
      def mark_warning_sent(receipt_id)
        warnings_sent.add(receipt_id)
      end

      # Remove expired entries from the timeline (self-cleaning)
      # @param before_timestamp [Float] Remove entries with score before this timestamp
      # @return [Integer] Number of entries removed
      def cleanup_expired_from_timeline(before_timestamp)
        expiration_timeline.remrangebyscore(0, before_timestamp)
      end
    end
  end
end
