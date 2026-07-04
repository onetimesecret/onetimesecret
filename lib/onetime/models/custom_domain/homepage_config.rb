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

      # Recognised disabled-homepage variants (mirrors the frontend
      # disabledHomepageVariantSchema). Anything else is treated as nil so the
      # domain falls back to the deployment-wide / frontend default.
      VALID_DISABLED_HOMEPAGE_VARIANTS = %w[v1 minimal closed].freeze

      # Recognised homepage secrets modes. When the homepage is enabled,
      # this selects WHICH interactive experience anonymous visitors get:
      #   'create'   - the classic secret-creation form (historical behavior)
      #   'incoming' - the incoming-secrets form (send a secret TO the
      #                domain's configured IncomingConfig recipients)
      # Unset/unknown values coerce to 'create' so records that pre-date this
      # field keep their existing behavior. Not to be confused with the
      # site-level homepage "mode" (internal/external CIDR detection in
      # Helpers::HomepageModeHelpers) — that gates WHO sees the interactive
      # homepage; this selects WHAT the interactive homepage is.
      VALID_SECRETS_MODES  = %w[create incoming].freeze
      DEFAULT_SECRETS_MODE = 'create'

      prefix :custom_domain__homepage_config

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one homepage config per domain.
      identifier_field :domain_id
      field :domain_id

      # Whether homepage secrets is enabled for this domain
      field :enabled

      # Per-domain UI toggles for the homepage auth nav. Both default to false
      # (conservative, mirroring SigninConfig/SignupConfig): a freshly created
      # domain hides the Create Account / Sign In links until an operator
      # explicitly opts in via PUT /homepage-config. A missing field (legacy
      # records that pre-date this feature) also reads as disabled. The
      # system-level site.authentication.{signup,signin} flags remain the
      # master switch — the frontend ANDs both layers, so toggling a system
      # flag off hides the link regardless of this domain-level value.
      field :signup_enabled
      field :signin_enabled

      # Which disabled-homepage variant this domain renders when the homepage
      # secret form is gated by auth. nil (unset) = fall back to the
      # deployment-wide default (site.interface.ui.homepage.disabled_variant)
      # and ultimately the frontend DEFAULT_DISABLED_HOMEPAGE_VARIANT constant.
      field :disabled_homepage_variant

      # Which interactive experience the homepage offers when enabled
      # ('create' | 'incoming'). nil/unset (legacy records) reads as 'create'
      # via secrets_mode_value, preserving pre-existing behavior.
      field :secrets_mode

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled      ||= 'false'
        self.signup_enabled = false if signup_enabled.nil?
        self.signin_enabled = false if signin_enabled.nil?
        # init runs for new objects only (Familia loads via allocate), so this
        # makes freshly created records self-describing without masking legacy
        # records' nil field — those still read as 'create' via secrets_mode_value.
        self.secrets_mode ||= DEFAULT_SECRETS_MODE
      end

      # Check if homepage secrets is enabled for this domain.
      #
      # @return [Boolean] true if homepage secrets is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Whether the Sign Up link should render on this domain's homepage.
      # Conservative default: only an explicit boolean `true` shows the link.
      # A missing/nil field (legacy records pre-dating this field) reads as
      # false, so the link stays hidden until an operator opts in. A stray
      # string value ('true'/'false') is likewise treated as disabled.
      def signup_enabled?
        signup_enabled == true
      end

      # Whether the Sign In link should render on this domain's homepage.
      # Conservative default: only an explicit boolean `true` shows the link.
      def signin_enabled?
        signin_enabled == true
      end

      # Recognised disabled-homepage variant for this domain, or nil to fall
      # back to the deployment-wide / frontend default. Guards against blank or
      # stale values in Redis (records pre-dating this field have none).
      def disabled_homepage_variant_value
        self.class.coerce_disabled_homepage_variant(disabled_homepage_variant)
      end

      # Effective homepage secrets mode ('create' | 'incoming'). Records that
      # pre-date the field (nil) and stray/unknown values both read as
      # 'create' so legacy domains keep their historical behavior.
      def secrets_mode_value
        self.class.coerce_secrets_mode(secrets_mode)
      end

      # Whether this domain's homepage presents the incoming-secrets form
      # (rather than the classic secret-creation form) when enabled.
      def incoming_mode?
        secrets_mode_value == 'incoming'
      end

      # Whether the homepage is EFFECTIVELY interactive for anonymous
      # visitors right now. For create mode this is just enabled?; for
      # incoming mode it additionally requires that incoming can actually
      # receive secrets (see incoming_available?). This is the single
      # source of truth consumed by both the bootstrap serializer (read
      # path) and the homepage-config API responses, so the two can never
      # drift: a homepage pointed at an unavailable incoming form fails
      # closed to the non-interactive trust card.
      #
      # @param custom_domain [CustomDomain, nil] pass the already-loaded
      #   domain to avoid a redundant Redis read; falls back to loading it.
      # @return [Boolean]
      def effectively_enabled?(custom_domain: nil)
        return false unless enabled?
        return true unless incoming_mode?

        incoming_available?(custom_domain: custom_domain)
      end

      # Whether the domain can actually serve the incoming form to
      # anonymous visitors: instance feature flag on, site.secret present
      # (recipient hashes cannot be computed without it — RecipientResolver
      # fails closed the same way), IncomingConfig ready (enabled with at
      # least one recipient), and the owning org still entitled. Mirrors
      # the PutHomepageConfig secrets_mode=incoming write gate. Checks run
      # cheapest-first (in-memory config, one Redis read, org load).
      #
      # @param custom_domain [CustomDomain, nil] optional pre-loaded domain
      # @return [Boolean]
      def incoming_available?(custom_domain: nil)
        return false unless OT.conf.dig('features', 'incoming', 'enabled')
        return false if OT.conf.dig('site', 'secret').to_s.strip.empty?

        incoming = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(domain_id)
        return false unless incoming&.ready?

        domain = custom_domain || self.custom_domain
        domain&.primary_organization&.can?('incoming_secrets') || false
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
        unless disabled_homepage_variant.to_s.empty? ||
               VALID_DISABLED_HOMEPAGE_VARIANTS.include?(disabled_homepage_variant.to_s)
          errors << "invalid disabled_homepage_variant: #{disabled_homepage_variant}"
        end
        unless secrets_mode.to_s.empty? || VALID_SECRETS_MODES.include?(secrets_mode.to_s)
          errors << "invalid secrets_mode: #{secrets_mode}"
        end
        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      class << self
        # Normalise a disabled-homepage variant to a recognised id, or nil
        # (= use the deployment-wide / frontend default). Blank and unknown
        # values both collapse to nil.
        def coerce_disabled_homepage_variant(value)
          v = value.to_s.strip
          VALID_DISABLED_HOMEPAGE_VARIANTS.include?(v) ? v : nil
        end

        # Normalise a homepage secrets mode to a recognised id. Blank and
        # unknown values collapse to DEFAULT_SECRETS_MODE ('create') so
        # legacy records and stray Redis values keep historical behavior.
        def coerce_secrets_mode(value)
          v = value.to_s.strip
          VALID_SECRETS_MODES.include?(v) ? v : DEFAULT_SECRETS_MODE
        end

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
        # @param enabled [Boolean, String] Whether to enable homepage secrets.
        #   Required by every call site; passing nil coerces to the string
        #   "nil", which #enabled? reads as false — the safe default, but
        #   not a validated one, so don't rely on this to reject bad input.
        # @param disabled_homepage_variant [String, nil] Merge semantics, matching
        #   signup_enabled/signin_enabled: nil leaves the stored value unchanged;
        #   "" (or any unrecognised value) clears the override back to the default;
        #   a recognised id ('v1' | 'minimal' | 'closed') sets it.
        # @param secrets_mode [String, nil] Merge semantics: nil leaves the stored
        #   value unchanged; "" (or any unrecognised value) resets to 'create';
        #   a recognised id ('create' | 'incoming') sets it.
        # @return [CustomDomain::HomepageConfig] The config (created or updated)
        def upsert(domain_id:, enabled:, signup_enabled: nil, signin_enabled: nil, disabled_homepage_variant: nil, secrets_mode: nil)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          now    = Familia.now.to_i

          if config
            config.created                 ||= now  # repair missing created from legacy records
            config.enabled                   = enabled.to_s
            config.signup_enabled            = signup_enabled unless signup_enabled.nil?
            config.signin_enabled            = signin_enabled unless signin_enabled.nil?
            config.disabled_homepage_variant = coerce_disabled_homepage_variant(disabled_homepage_variant) unless disabled_homepage_variant.nil?
            config.secrets_mode              = coerce_secrets_mode(secrets_mode) unless secrets_mode.nil?
            config.updated                   = now
          else
            config = new(
              domain_id: domain_id,
              enabled: enabled.to_s,
              signup_enabled: signup_enabled.nil? ? false : signup_enabled,
              signin_enabled: signin_enabled.nil? ? false : signin_enabled,
              disabled_homepage_variant: coerce_disabled_homepage_variant(disabled_homepage_variant),
              secrets_mode: coerce_secrets_mode(secrets_mode),
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
            signup_enabled: signup_enabled.nil? ? false : signup_enabled,
            signin_enabled: signin_enabled.nil? ? false : signin_enabled,
            secrets_mode: DEFAULT_SECRETS_MODE,
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
          if attrs.key?(:disabled_homepage_variant)
            config.disabled_homepage_variant = coerce_disabled_homepage_variant(attrs[:disabled_homepage_variant])
          end
          config.secrets_mode   = coerce_secrets_mode(attrs[:secrets_mode]) if attrs.key?(:secrets_mode)

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
