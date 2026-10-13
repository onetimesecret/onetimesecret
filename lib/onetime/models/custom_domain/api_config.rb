# lib/onetime/models/custom_domain/api_config.rb
#
# frozen_string_literal: true

require_relative '../features/boolean_encoding'
require_relative '../features/guarded_config_writes'

#
# CustomDomain::ApiConfig - Per-domain API access configuration
#
# This model stores API access configuration bound to a specific CustomDomain.
# When enabled, anonymous users can use the API against this domain.
#
# This is the single source of truth for API access settings. The legacy
# allow_public_api field on BrandSettings was retired in #3026 once the
# #3023 backfill migration guaranteed every CustomDomain has a record.
# CustomDomain.create! bootstraps a default-disabled record so the
# invariant holds for new domains as well.
#
# @see HomepageConfig - Similar pattern for homepage secrets
# @see IncomingConfig - Similar pattern for incoming secrets recipients
#
class Onetime::CustomDomain::ApiConfig < Familia::Horreum
  include Familia::Features::Autoloader

  SCHEMA = 'models/domain-api-config'

  prefix :custom_domain__api_config

  # domain_id is the CustomDomain's identifier (objid), used as our key.
  # This creates a 1:1 relationship: one API config per domain.
  identifier_field :domain_id
  field :domain_id

  # Whether public API access is enabled for this domain
  field :enabled

  # Timestamps (Unix epoch integers)
  field :created
  field :updated

  # Colonel-writable fields, aggregated into
  # {Onetime::CustomDomain::ConfigRegistry::FIELD_SPECS} (the registry
  # validates at load time that every key has a setter here). `enabled`
  # stores a legacy 'true'/'false' STRING; the boolean_encoding feature
  # (below) normalizes writes to that encoding and keeps #enabled?
  # tolerant of both (#3951).
  FIELD_SPECS = {
    'enabled' => { type: :boolean, storage: :string },
  }.freeze

  # Tolerant predicate + normalizing setter for `enabled` per the spec
  # above (#3951). Must come after both the field declaration and the
  # constant.
  feature :boolean_encoding
  feature :guarded_config_writes

  def init
    self.enabled ||= 'false'
  end

  # Enable public API access for this domain.
  # @return [void]
  def enable!
    self.enabled = 'true'
    self.updated = Familia.now.to_i
    save
  end

  # Disable public API access for this domain.
  # @return [void]
  def disable!
    self.enabled = 'false'
    self.updated = Familia.now.to_i
    save
  end

  # Load the associated CustomDomain record.
  #
  # @return [CustomDomain, nil] The domain or nil if not found
  def custom_domain
    Onetime::CustomDomain.find_by_identifier(domain_id)
  end

  # Load the owning Organization via the CustomDomain.
  #
  # @return [Organization, nil] The organization or nil if not found
  def organization
    domain = custom_domain
    return nil unless domain

    Onetime::Organization.load(domain.org_id)
  end

  # Validate configuration.
  #
  # @return [Array<String>] List of validation error messages
  def validation_errors
    errors = []
    errors << 'domain_id is required' if domain_id.to_s.empty?
    errors
  end

  # Check if the configuration is valid.
  #
  # @return [Boolean] true if no validation errors
  def valid?
    validation_errors.empty?
  end

  class << self
    # Find API config by domain ID.
    #
    # @param domain_id [String] CustomDomain identifier (objid)
    # @return [CustomDomain::ApiConfig, nil] The config or nil if not found
    def find_by_domain_id(domain_id)
      return nil if domain_id.to_s.empty?

      load(domain_id)
    end

    # Check if a domain has API config.
    #
    # @param domain_id [String] CustomDomain identifier
    # @return [Boolean] true if API config exists
    def exists_for_domain?(domain_id)
      return false if domain_id.to_s.empty?

      exists?(domain_id)
    end

    # Create or update API config for a domain.
    #
    # Prefer this over create! for PUT endpoints. A create lost to a
    # concurrent create updates the record that won (GuardedConfigWrites).
    #
    # @param domain_id [String] CustomDomain identifier
    # @param enabled [Boolean, String] Whether to enable API access
    # @return [CustomDomain::ApiConfig] The config (created or updated)
    def upsert(domain_id:, enabled:)
      raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

      now   = Familia.now.to_i
      build = -> { new(domain_id: domain_id, enabled: enabled.to_s, created: now, updated: now) }

      upsert_for_domain!(domain_id, 'API config already exists for this domain', build: build) do |config|
        config.created ||= now  # repair missing created from legacy records
        config.enabled   = enabled
        config.updated   = now
      end
    end

    # Atomically return an existing ApiConfig or create one if absent.
    #
    # Backfill/bootstrap counterpart to upsert. A concurrent writer that
    # created a record between the caller's read and our write gets their
    # value preserved — this method never overwrites an existing record.
    # Uses Familia's WATCH-based save_if_not_exists! so the exists-check
    # and save participate in the same optimistic transaction.
    #
    # @param domain_id [String] CustomDomain identifier
    # @param enabled   [Boolean, String] value to use only if creating
    # @return [Array(ApiConfig, Symbol)] [config, :created | :existed]
    def find_or_create_for_domain(domain_id:, enabled:)
      raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

      existing = find_by_domain_id(domain_id)
      return [existing, :existed] if existing

      now    = Familia.now.to_i
      config = new(domain_id: domain_id, enabled: enabled.to_s, created: now, updated: now)

      begin
        config.save_if_not_exists!
        [config, :created]
      rescue Familia::RecordExistsError
        # A racing writer's record existed inside Familia's WATCH block.
        # Re-read must succeed: if it doesn't, the record vanished between
        # WATCH and re-read (concurrent destroy, TTL eviction, test teardown).
        # Raise rather than silently return [nil, :existed] and break the
        # method contract.
        found = find_by_domain_id(domain_id)
        raise Onetime::Problem, "ApiConfig for #{domain_id} vanished after conflict" unless found

        [found, :existed]
      end
    end

    # Create a new API config for a domain.
    #
    # @param domain_id [String] CustomDomain identifier
    # @param attrs [Hash] Configuration attributes
    # @return [CustomDomain::ApiConfig] The created config
    # @raise [Onetime::Problem] if config already exists
    def create!(domain_id:, **attrs)
      raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

      exists_message = 'API config already exists for this domain'
      refuse_existing_config!(domain_id, exists_message)

      config = new(domain_id: domain_id)

      config.enabled = attrs[:enabled].to_s if attrs.key?(:enabled)

      now            = Familia.now.to_i
      config.created = now
      config.updated = now

      save_new_config!(config, exists_message)
      config
    end
  end
end
