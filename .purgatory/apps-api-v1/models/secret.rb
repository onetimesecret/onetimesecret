# apps/api/v1/models/secret.rb

require_relative 'mixins/passphrase'

module V1
  class Secret < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    feature :safe_dump
    feature :expiration

    default_expiration 7.days # default only, can be overridden at create time
    prefix :secret

    identifier_field :key

    field :custid
    field :state
    field :value
    field :metadata_key
    field :original_size
    field :value_encryption
    field :lifespan
    field :share_domain
    field :verification
    field :updated
    field :created
    field :truncated # boolean

    # See note on Onetime::Secret
    field :key

    counter :view_count, default_expiration: 14.days # out lives the secret itself

    # NOTE: this field is a nullop. It's only populated if a value was entered
    # into a hidden field which is something a regular person would not do.
    field :token

    safe_dump_field :identifier, ->(obj) { obj.identifier }
    safe_dump_field :key
    safe_dump_field :state
    safe_dump_field :secret_ttl, ->(m) { m.lifespan }
    safe_dump_field :lifespan
    safe_dump_field :original_size
    safe_dump_field :shortid, ->(m) { m.identifier.slice(0, 8) }
    safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
    safe_dump_field :verification, ->(m) { m.verification? }
    safe_dump_field :is_truncated, ->(m) { m.truncated? }
    safe_dump_field :created
    safe_dump_field :updated

    def init
      self.state ||= 'new'
      self.key ||= self.class.generate_id # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def shortid
      key.slice(0,6)
    end

    def age
      @age ||= Familia.now.to_i-self.updated
      @age
    end

    def expiration
      # Unix timestamp of when this secret will expire. Based on
      # the secret's TTL (lifespan) and the created time of the secret.
      lifespan.to_i + created.to_i if lifespan
    end

    # Alias for compatibility with controller expectations
    alias_method :current_expiration, :expiration

    def natural_duration
      # Colloquial representation of the TTL. e.g. "1 day"
      V1::TimeUtils.natural_duration lifespan
    end

    def older_than? seconds
      age > seconds
    end

    def valid?
      exists? && !value.to_s.empty?
    end

    def truncated?
      self.truncated.to_s == "true"
    end

    def verification?
      verification.to_s == "true"
    end

    def encrypt_value original_value, opts={}
      if opts[:size] && original_value.size > opts[:size]
        storable_value = original_value.slice(0, opts[:size])
        self.truncated = true
      else
        storable_value = original_value
      end

      self.original_size = original_value.size
      self.value_encryption = 2
      self.value = storable_value.encrypt opts.merge(:key => encryption_key)
    end

    def decrypted_value opts={}
      v_encrypted = self.value
      v_encrypted.force_encoding("utf-8")
      v_decrypted = case value_encryption.to_i
      when 0
        v_encrypted
      when 1
        v_encrypted.decrypt opts.merge(:key => encryption_key_v1)
      when 2
        v_encrypted.decrypt opts.merge(:key => encryption_key_v2)
      else
        raise RuntimeError, "Unknown encryption mode: #{value_encryption}"
      end
      v_decrypted.force_encoding("utf-8") # Hacky fix for https://github.com/onetimesecret/onetimesecret/issues/37
      v_decrypted
    end

    def can_decrypt?
      !value.to_s.empty?  && (passphrase.to_s.empty? || !passphrase_temp.to_s.empty?)
    end

    def encryption_key *args
      case value_encryption.to_i
      when 0
        self.value
      when 1  # Last used 2012-01-07
        encryption_key_v1(*args)
      when 2
        encryption_key_v2(*args)
      else
        raise RuntimeError, "Unknown encryption mode: #{value_encryption}"
      end
    end

    def encryption_key_v1 *ignored
      V1::Secret.encryption_key self.key, self.passphrase_temp
    end

    def encryption_key_v2 *ignored
      V1::Secret.encryption_key OT.global_secret, self.key, self.passphrase_temp
    end

    def load_customer
      cust = V1::Customer.load custid
      cust.nil? ? V1::Customer.anonymous : cust # TODO: Probably should simply return nil (see defensive "fix" in 23c152)
    end

    def state? guess
      state.to_s.eql?(guess.to_s)
    end

    def load_metadata
      V1::Metadata.load metadata_key
    end

    def anonymous?
      custid.to_s == 'anon'
    end

    def owner? cust
      !anonymous? && (cust.is_a?(V1::Customer) ? cust.custid : cust).to_s == custid.to_s
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
      md = load_metadata
      md.received! unless md.nil?
      # It's important for the state to change here, even though we're about to
      # destroy the secret. This is because the state is used to determine if
      # the secret is viewable. If we don't change the state here, the secret
      # will still be viewable b/c (state?(:new) || state?(:viewed) == true).
      @state = 'received'
      # We clear the value and passphrase_temp immediately so that the secret
      # payload is not recoverable from this instance of the secret; however,
      # we shouldn't clear arbitrary fields here b/c there are valid reasons
      # to be able to call secret.safe_dump for example. This is exactly what
      # happens in Logic::RevealSecret.process which prepares the secret value
      # to be included in the response and then calls this method att the end.
      # It's at that point that `Logic::RevealSecret.success_data` is called
      # which means if we were to clear out say -- original_size -- it would
      # be null in the API's JSON response. Not a huge deal in that case, but
      # we validate response data in the UI now and this would raise an error.
      @value = nil
      @passphrase_temp = nil
      self.destroy!
    end

    def burned!
      # A guard to allow only a fresh, new secret to be burned. Also ensures that
      # we don't support going from :burned back to something else.
      return unless state?(:new) || state?(:viewed)
      md = load_metadata
      md.burned! unless md.nil?
      @passphrase_temp = nil
      self.destroy!
    end

    class << self

      def spawn_pair custid, token=nil
        secret = V1::Secret.create(custid: custid, token: token)
        metadata = V1::Metadata.create(custid: custid, token: token)

        p [:spawn_pair, secret.exists?, metadata.exists?]
        # TODO: Use Familia transaction
        metadata.secret_key = secret.key
        metadata.save

        secret.metadata_key = metadata.key
        secret.save

        [metadata, secret]
      end

      def encryption_key *entropy
        input = entropy.flatten.compact.join ':'
        Digest::SHA256.hexdigest(input) # TODO: Use Familila.generate_id
      end

      def generate_id
        Familia.generate_id
      end

    end

    # See Customer model for explanation about why
    # we include extra fields at the end here.
    include V1::Mixins::Passphrase
  end
end
