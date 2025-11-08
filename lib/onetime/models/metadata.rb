# lib/onetime/models/metadata.rb

module Onetime
  class Metadata < Familia::Horreum
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

    default_expiration 14.days # by default 2x Secret.default_expiration
    prefix :metadata

    identifier_field :objid

    field :owner_id
    field :state
    field :secret_identifier
    field :secret_shortid
    field :secret_ttl
    field :lifespan
    field :share_domain
    field :passphrase

    # NOTE: There is no `expired` timestamp field since we can calculate
    # that based on the `secret_ttl` and the `created` timestamp. See
    # the secret_expired? and expiration methods.
    field :recipients

    def init
      self.state ||= 'new'
    end

    def age
      @age ||= Familia.now.to_i - updated
      @age
    end

    def metadata_ttl
      # Stay alive for twice as long as the secret so that we can
      # provide the metadata page even after the secret is gone.
      (secret_ttl.to_i * 2) if secret_ttl.to_i > 0
    end
    alias expiration_in_seconds metadata_ttl

    def expiration
      # Unix timestamp of when the metadata will expire. Based on
      # the secret_ttl and the created time of the metadata.
      metadata_ttl.to_i + created.to_i if metadata_ttl
    end

    def natural_duration
      # Colloquial representation of the TTL. e.g. "1 day"
      OT::Utils::TimeUtils.natural_duration metadata_ttl
    end

    def secret_expiration
      # Unix timestamp of when the secret will expire. Based on
      # the secret_ttl and the created time of the metadata
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
      !passphrase.to_s.empty?
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

    class << self
      def generate_id
        Familia.generate_id
      end

      def spawn_pair(owner_id, lifespan, content, passphrase: nil, domain: nil)

        secret   = Onetime::Secret.new(owner_id: owner_id)
        metadata = Onetime::Metadata.new(owner_id: owner_id)

        metadata.secret_identifier = secret.objid
        metadata.default_expiration = lifespan * 2
        metadata.save

        secret.default_expiration = lifespan
        secret.lifespan = lifespan
        secret.metadata_identifier = metadata.objid

        secret.share_domain = domain
        secret.ciphertext_domain = domain # transient fields need to be populated before
        secret.passphrase = passphrase # encrypting the content fio aad protection
        secret.ciphertext = content
        secret.save

        metadata.secret_shortid = secret.shortid
        metadata.secret_ttl = lifespan
        metadata.lifespan = lifespan
        metadata.share_domain = domain
        metadata.passphrase = passphrase if passphrase
        metadata.save

        [metadata, secret]
      end
    end

  end
end
