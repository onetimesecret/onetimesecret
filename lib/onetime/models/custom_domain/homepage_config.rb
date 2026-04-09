# lib/onetime/models/custom_domain/homepage_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::HomepageConfig - Per-domain homepage secrets configuration
#
# This model stores homepage configuration bound to a specific CustomDomain.
# When enabled, anonymous users can create secrets on the domain's public
# homepage without authentication.
#
# This is the canonical source for homepage settings, replacing the legacy
# allow_public_homepage field stored in BrandSettings. During migration,
# CustomDomain#allow_public_homepage? checks HomepageConfig first, then
# falls back to BrandSettings.
#
# @see IncomingConfig - Similar pattern for incoming secrets recipients
#
module Onetime
  class CustomDomain < Familia::Horreum
    class HomepageConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-homepage-config'

      prefix :custom_domain__homepage_config

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one homepage config per domain.
      identifier_field :domain_id
      field :domain_id

      # Whether homepage secrets is enabled for this domain
      field :enabled

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled ||= 'false'
      end

      # Check if homepage secrets is enabled for this domain.
      #
      # @return [Boolean] true if homepage secrets is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Enable homepage secrets for this domain.
      # @return [void]
      def enable!
        self.enabled = 'true'
        self.updated = Familia.now.to_i
        save
      end

      # Disable homepage secrets for this domain.
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
        # Find homepage config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::HomepageConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Check if a domain has homepage config.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if homepage config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create or update homepage config for a domain.
        #
        # Prefer this over create! for PUT endpoints: reduces the chance of a
        # duplicate-create error under concurrent requests. Last write wins for
        # the same domain_id key; created timestamp may reflect the second writer
        # on a first-write race. Not fully atomic — use a Lua script if strict
        # once-only create semantics are needed.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param enabled [Boolean, String] Whether to enable homepage secrets
        # @return [CustomDomain::HomepageConfig] The config (created or updated)
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

        # Create a new homepage config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::HomepageConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Homepage config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          config.enabled = attrs[:enabled].to_s if attrs.key?(:enabled)

          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          config.save
          config
        end

        # Delete homepage config for a domain.
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
