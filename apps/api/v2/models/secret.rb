# apps/api/v2/models/secret.rb

require 'openssl'

module V2
  class Secret < Familia::Horreum

    feature :safe_dump
    feature :expiration

    default_expiration 7.days # default only, can be overridden at create time
    prefix :secret

    identifier_field :key

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
    ].freeze

    def init
      self.state ||= 'new'
    end

    def generate_id
      @key ||= Familia.generate_id.slice(0, 31)
      @key
    end

    def shortkey
      key.slice(0, 6)
    end

    def maxviews
      1
    end

    # TODO: Remove. If we get around to support some manner of "multiple views"
    # it would be implmented as separate secrets with the same value. All of them
    # viewable only once.
    def maxviews?
      view_count.to_s.to_i >= maxviews
    end

    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end

    def expiration
      # Unix timestamp of when this secret will expire. Based on
      # the secret's TTL (lifespan) and the created time of the secret.
      lifespan.to_i + created.to_i if lifespan
    end

    def natural_duration
      # Colloquial representation of the TTL. e.g. "1 day"
      OT::TimeUtils.natural_duration lifespan
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

    def encrypt_value(original_value, opts = {})
      # Handles empty values with a special encryption flag. This is important
      # for consistency in how we deal with these values and expressly for Ruby
      # 3.1 which uses an older version of openssl that does not tolerate empty
      # strings like the more progressive 3.2+ Rubies.
      if original_value.to_s.empty?
        self.value_encryption = -1
        return
      end

      # Determine if the secret exceeds the configured size threshold
      if opts[:size] && original_value.length >= opts[:size]
        # Apply randomized truncation to mitigate information leakage. By
        # varying the actual truncation point by 0-20%, we prevent attackers
        # from inferring the exact content length, which could leak information
        # about the secret's contents.
        random_factor = 1.0 + (rand * 0.2)  # Random factor between 1.0-1.2
        adjusted_size = (opts[:size] * random_factor).to_i

        # The random factor already ensures fuzziness up to 20% above base
        # size. This ensures unpredictable truncation points within a
        # controlled range.
        storable_value = original_value.slice(0, adjusted_size)
        self.truncated = true
      else
        storable_value = original_value
      end
      # Secure the value with cryptographic encryption
      self.value_encryption = 2 # Current encryption version

      encryption_options = opts.merge(key: encryption_key)
      self.value         = storable_value.encrypt encryption_options
    end

    def decrypted_value(opts = {})
      encryption_mode = value_encryption.to_i
      v_encrypted     = value
      v_encrypted     = '' if encryption_mode.negative? && v_encrypted.nil?
      v_encrypted.force_encoding('utf-8')

      # First try with the primary global secret
      begin
        v_decrypted = case encryption_mode
        when -1
          ''
        when 0
          v_encrypted
        when 1
          v_encrypted.decrypt opts.merge(key: encryption_key_v1)
        when 2
          v_encrypted.decrypt opts.merge(key: encryption_key_v2)
        else
          raise "Unknown encryption mode: #{value_encryption}"
        end
        v_decrypted.force_encoding('utf-8') # Hacky fix for https://github.com/onetimesecret/onetimesecret/issues/37
        v_decrypted
      rescue OpenSSL::Cipher::CipherError => ex
        OT.le "[decrypted_value] m:#{metadata_key} s:#{key} CipherError #{ex.message}"
        # Try fallback global secrets for mode 2 (current encryption)
        if encryption_mode == 2 && fallback_secrets?
          fallback_result = try_fallback_secrets(v_encrypted, opts)
          return fallback_result if fallback_result
        end

        # If all secrets fail, try nil secret if allowed
        allow_nil = OT.conf[:experimental].fetch(:allow_nil_global_secret, false)
        if allow_nil
          OT.li "[decrypted_value] m:#{metadata_key} s:#{key} Trying nil global secret"
          decryption_options = opts.merge(key: encryption_key_v2_with_nil)
          return v_encrypted.decrypt(decryption_options)
        end

        # If nothing works, raise the original error
        raise ex
      end
    end

    # Check if there are additional global secrets configured beyond the primary one
    def fallback_secrets?
      rotated_secrets = OT.conf[:experimental].fetch(:rotated_secrets, [])
      rotated_secrets.is_a?(Array) && rotated_secrets.length > 1
    end

    # Try to decrypt using each fallback secret
    def try_fallback_secrets(encrypted_value, opts)
      return nil unless fallback_secrets?

      rotated_secrets = OT.conf[:experimental].fetch(:rotated_secrets, [])
      OT.ld "[try_fallback_secrets] m:#{metadata_key} s:#{key} Trying rotated secrets (#{rotated_secrets.length})"
      rotated_secrets.each_with_index do |fallback_secret, index|
          # Generate key using the fallback secret
          encryption_key = V2::Secret.encryption_key(fallback_secret, key, passphrase_temp)
          result         = encrypted_value.decrypt(opts.merge(key: encryption_key))
          result.force_encoding('utf-8')
          OT.li "[try_fallback_secrets] m:#{metadata_key} s:#{key} Success (index #{index})"
          return result
      rescue OpenSSL::Cipher::CipherError
          # Continue to next secret if this one fails
          OT.ld "[try_fallback_secrets] m:#{metadata_key} s:#{key} Failed (index #{index})"
          next
      end
      nil # Return nil if all fallback secrets fail
    end

    def can_decrypt?
      !value.to_s.empty?  && (passphrase.to_s.empty? || !passphrase_temp.to_s.empty?)
    end

    def encryption_key(*)
      case value_encryption.to_i
      when 0
        value
      when 1  # Last used 2012-01-07
        encryption_key_v1(*)
      when 2
        encryption_key_v2(*)
      else
        raise "Unknown encryption mode: #{value_encryption}"
      end
    end

    def encryption_key_v1 *_ignored
      V2::Secret.encryption_key key, passphrase_temp
    end

    def encryption_key_v2 *_ignored
      site_secret = OT.conf['site']['secret'] # aka previously called global_secret
      V2::Secret.encryption_key site_secret, key, passphrase_temp
    end

    # Used as a failover key when experimental.allow_nil_global_secret is true.
    def encryption_key_v2_with_nil
      V2::Secret.encryption_key nil, key, passphrase_temp
    end

    def load_customer
      cust = V2::Customer.load custid
      cust.nil? ? V2::Customer.anonymous : cust # TODO: Probably should simply return nil (see defensive "fix" in 23c152)
    end

    def state?(guess)
      state.to_s.eql?(guess.to_s)
    end

    def load_metadata
      V2::Metadata.load metadata_key
    end

    def anonymous?
      custid.to_s == 'anon'
    end

    def owner?(cust)
      !anonymous? && (cust.is_a?(V2::Customer) ? cust.custid : cust).to_s == custid.to_s
    end

    def viewable?
      key?(:value) && (state?(:new) || state?(:viewed))
    end

    def receivable?
      key?(:value) && (state?(:new) || state?(:viewed))
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

    class << self
      def spawn_pair(custid, token = nil)
        secret   = V2::Secret.create(custid: custid, token: token)
        metadata = V2::Metadata.create(custid: custid, token: token)

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
    end

    # See Customer model for explanation about why
    # we include extra fields at the end here.
    include V2::Mixins::Passphrase
  end
end
