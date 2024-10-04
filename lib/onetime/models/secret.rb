
module Onetime
  class Secret < Familia::Horreum
    include Gibbler::Complex

    feature :safe_dump
    feature :expiration

    db 8
    ttl 7.days # default only, can be overridden at create time
    prefix :secret

    identifier :generate_id

    field :custid
    field :state
    field :value
    field :metadata_key
    field :original_size
    field :value_checksum
    field :value_encryption
    field :lifespan
    field :share_domain
    field :verification
    field :updated
    field :created
    field :truncated # boolean
    field :maxviews # always 1 (here for backwards compat)

    counter :view_count, ttl: 14.days # out lives the secret itself

    # NOTE: this field is a nullop. It's only populated if a value was entered
    # into a hidden field which is something a regular person would not do.
    field :token

    def init
      self.state ||= 'new'
    end

    def generate_id
      @key ||= Familia.generate_id.slice(0, 31)
      @key
    end

    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end

    def customer?
      ! custid.nil?
    end

    def value_length
      value.to_s.size
    end

    def long
      original_size >= 5000
    end

    def shortkey
      key.slice(0,6)
    end

    def maxviews
      1
    end

    # TODO: Remove. If we get around to support some manner of "multiple views"
    # it would be implmented as separate secrets with the same value. All of them
    # viewable only once.
    def maxviews?
      self.view_count.to_s.to_i >= self.maxviews
    end

    def viewable?
      has_key?(:value) && (state?(:new) || !maxviews?)
    end

    def age
      @age ||= Time.now.utc.to_i-self.updated
      @age
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

    def encrypt_value original_value, opts={}
      if opts[:size] && original_value.size > opts[:size]
        storable_value = original_value.slice(0, opts[:size])
        self.truncated = true
      else
        storable_value = original_value
      end

      self.original_size = original_value.size
      self.value_checksum = storable_value.gibbler
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
      OT::Secret.encryption_key self.key, self.passphrase_temp
    end

    def encryption_key_v2 *ignored
      OT::Secret.encryption_key OT.global_secret, self.key, self.passphrase_temp
    end

    def load_customer
      cust = OT::Customer.load custid
      cust.nil? ? OT::Customer.anonymous : cust # TODO: Probably should simply return nil (see defensive "fix" in 23c152)
    end

    def state? guess
      state.to_s.eql?(guess.to_s)
    end

    def load_metadata
      OT::Metadata.load metadata_key
    end

    def anonymous?
      custid.to_s == 'anon'
    end

    def owner? cust
      !anonymous? && (cust.is_a?(OT::Customer) ? cust.custid : cust).to_s == custid.to_s
    end

    def received!
      # A guard to allow only a fresh, new secret to be received. Also ensures that
      # we don't support going from :viewed back to something else.
      return unless state?(:new)
      md = load_metadata
      md.received! unless md.nil?
      @passphrase_temp = nil
      self.destroy!
    end

    def burned!
      # A guard to allow only a fresh, new secret to be burned. Also ensures that
      # we don't support going from :burned back to something else.
      return unless state?(:new)
      load_metadata.burned!
      @passphrase_temp = nil
      self.destroy!
    end

    class << self

      def spawn_pair custid, token=nil
        secret = OT::Secret.create(custid: custid, token: token)
        metadata = OT::Metadata.create(custid: custid, token: token)

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
    include Onetime::Models::Passphrase
  end
end
