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
# This is the single source of truth for homepage settings. The legacy
# allow_public_homepage field on BrandSettings was retired in #3026 once
# the #3023 backfill migration guaranteed every CustomDomain has a record.
# CustomDomain.create! bootstraps a default-disabled record so the
# invariant holds for new domains as well.
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

      # Per-domain UI toggles for the homepage auth nav. Both default to true
      # so existing records (no field set) render the links. The system-level
      # site.authentication.{signup,signin} flags remain the master switch:
      # the frontend ANDs both layers, so toggling a system flag off hides
      # the link regardless of this domain-level value.
      field :signup_enabled
      field :signin_enabled

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled      ||= 'false'
        self.signup_enabled = true if signup_enabled.nil?
        self.signin_enabled = true if signin_enabled.nil?
      end

      # Check if homepage secrets is enabled for this domain.
      #
      # @return [Boolean] true if homepage secrets is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Whether the Sign Up link should render on this domain's homepage.
      # Records pre-dating this field return nil, which we treat as enabled
      # (only an explicit `false` hides the link).
      def signup_enabled?
        signup_enabled != false
      end

      # Whether the Sign In link should render on this domain's homepage.
      def signin_enabled?
        signin_enabled != false
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
        def upsert(domain_id:, enabled:, signup_enabled: nil, signin_enabled: nil)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          now    = Familia.now.to_i

          if config
            config.created      ||= now  # repair missing created from legacy records
            config.enabled        = enabled.to_s
            config.signup_enabled = signup_enabled unless signup_enabled.nil?
            config.signin_enabled = signin_enabled unless signin_enabled.nil?
            config.updated        = now
          else
            config = new(
              domain_id: domain_id,
              enabled: enabled.to_s,
              signup_enabled: signup_enabled.nil? || signup_enabled,
              signin_enabled: signin_enabled.nil? || signin_enabled,
              created: now,
              updated: now,
            )
          end

          config.save
          config
        end

        # Atomically return an existing HomepageConfig or create one if absent.
        #
        # Backfill/bootstrap counterpart to upsert. A concurrent writer that
        # created a record between the caller's read and our write gets their
        # value preserved — this method never overwrites an existing record.
        # Uses Familia's WATCH-based save_if_not_exists! so the exists-check
        # and save participate in the same optimistic transaction.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param enabled   [Boolean, String] value to use only if creating
        # @return [Array(HomepageConfig, Symbol)] [config, :created | :existed]
        def find_or_create_for_domain(domain_id:, enabled:, signup_enabled: nil, signin_enabled: nil)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

          existing = find_by_domain_id(domain_id)
          return [existing, :existed] if existing

          now    = Familia.now.to_i
          config = new(
            domain_id: domain_id,
            enabled: enabled.to_s,
            signup_enabled: signup_enabled.nil? || signup_enabled,
            signin_enabled: signin_enabled.nil? || signin_enabled,
            created: now,
            updated: now,
          )

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
            raise Onetime::Problem, "HomepageConfig for #{domain_id} vanished after conflict" unless found

            [found, :existed]
          end
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

          config.enabled        = attrs[:enabled].to_s if attrs.key?(:enabled)
          config.signup_enabled = attrs[:signup_enabled] if attrs.key?(:signup_enabled)
          config.signin_enabled = attrs[:signin_enabled] if attrs.key?(:signin_enabled)

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
