# lib/onetime/models/custom_domain/api_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::ApiConfig - Per-domain API access configuration
#
# This model stores API access configuration bound to a specific CustomDomain.
# When enabled, anonymous users can use the API against this domain.
#
# This is the canonical source for API access settings, replacing the legacy
# allow_public_api field stored in BrandSettings. During migration,
# CustomDomain#allow_public_api? checks ApiConfig first, then falls back
# to BrandSettings.
#
# @see HomepageConfig - Similar pattern for homepage secrets
# @see IncomingConfig - Similar pattern for incoming secrets recipients
#
module Onetime
  class CustomDomain < Familia::Horreum
    class ApiConfig < Familia::Horreum
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

      def init
        self.enabled ||= 'false'
      end

      # Check if public API access is enabled for this domain.
      #
      # @return [Boolean] true if public API access is active
      def enabled?
        enabled.to_s == 'true'
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
      rescue Onetime::RecordNotFound
        nil
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
        rescue Onetime::RecordNotFound
          nil
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
        # Prefer this over create! for PUT endpoints: reduces the chance of a
        # duplicate-create error under concurrent requests. Last write wins for
        # the same domain_id key; created timestamp may reflect the second writer
        # on a first-write race. Not fully atomic — use a Lua script if strict
        # once-only create semantics are needed.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param enabled [Boolean, String] Whether to enable API access
        # @return [CustomDomain::ApiConfig] The config (created or updated)
        def upsert(domain_id:, enabled:)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          now    = Familia.now.to_i

          if config
            config.created ||= now  # repair missing created from legacy records
            config.enabled   = enabled.to_s
            config.updated   = now
          else
            config = new(domain_id: domain_id, enabled: enabled.to_s, created: now, updated: now)
          end

          config.save
          config
        end

        # Create a new API config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::ApiConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'API config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          config.enabled = attrs[:enabled].to_s if attrs.key?(:enabled)

          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          config.save
          config
        end

        # Delete API config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if deleted, false if not found
        def delete_for_domain!(domain_id)
          return false if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          return false unless config

          config.destroy!
          true
        end
      end
    end
  end
end
