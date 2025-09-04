# apps/api/v2/models/secret.rb

require_relative 'secret/features'

module V2
  class Secret < Familia::Horreum
    include Familia::Features::Autoloader

    feature :safe_dump
    feature :expiration
    feature :relationships
    feature :object_identifier
    feature :required_fields
    feature :secret_encryption
    feature :secret_state_management
    feature :secret_customer_relations
    feature :secret_deprecated_fields

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
      self.key   ||= self.class.generate_id # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def shortkey
      key.slice(0, 6)
    end

    def age
      @age ||= Time.now.utc.to_i - updated
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

    def state?(guess)
      state.to_s.eql?(guess.to_s)
    end

    def load_metadata
      V2::Metadata.load metadata_key
    end

    def viewable?
      has_key?(:value) && (state?(:new) || state?(:viewed))
    end

    def receivable?
      has_key?(:value) && (state?(:new) || state?(:viewed))
    end

    def viewed!
      # A guard to prevent regressing (e.g. from :burned back to :viewed)
      return unless state?(:new)

      # The secret link has been accessed but the secret has not been consumed yet
      @state = 'viewed'
      # NOTE: calling save re-creates all fields so if you're relying on
      # has_field? to be false, it will start returning true after a save.
      save update_expiration: false
    end

    def received!
      # A guard to allow only a fresh, new secret to be received. Also ensures that
      # we don't support going from :viewed back to something else.
      return unless state?(:new) || state?(:viewed)

      md               = load_metadata
      md.received! unless md.nil?
      # It's important for the state to change here, even though we're about to
      # destroy the secret. This is because the state is used to determine if
      # the secret is viewable. If we don't change the state here, the secret
      # will still be viewable b/c (state?(:new) || state?(:viewed) == true).
      @state           = 'received'
      # We clear the value and passphrase_temp immediately so that the secret
      # payload is not recoverable from this instance of the secret; however,
      # we shouldn't clear arbitrary fields here b/c there are valid reasons
      # to be able to call secret.safe_dump for example. This is exactly what
      # happens in Logic::RevealSecret.process which prepares the secret value
      # to be included in the response and then calls this method att the end.
      # It's at that point that `Logic::RevealSecret.success_data` is called
      # which means if we were to clear out say -- state -- it would
      # be null in the API's JSON response. Not a huge deal in that case, but
      # we validate response data in the UI now and this would raise an error.
      @value           = nil
      @passphrase_temp = nil
      destroy!
    end

    def burned!
      # A guard to allow only a fresh, new secret to be burned. Also ensures that
      # we don't support going from :burned back to something else.
      return unless state?(:new) || state?(:viewed)

      md               = load_metadata
      md.burned! unless md.nil?
      @passphrase_temp = nil
      destroy!
    end

    # See Customer model for explanation about why
    # we include extra fields at the end here.
    include V2::Mixins::Passphrase
  end
end
