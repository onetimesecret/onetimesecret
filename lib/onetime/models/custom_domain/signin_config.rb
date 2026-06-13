# lib/onetime/models/custom_domain/signin_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::SigninConfig - Per-domain sign-in method configuration
#
# This model stores sign-in policy configuration bound to a specific CustomDomain.
# Enables per-tenant control over which authentication methods are available
# on the login page.
#
# Use Cases:
#   - SSO-only enforcement: secrets.corp.com restricts to SSO login
#   - Passwordless: secrets.modern.com restricts to email_auth (magic links)
#   - Method isolation: hide methods that aren't relevant for a domain's users
#
# Non-Nullable Override Semantics:
#   All boolean fields are non-nullable with conservative defaults (false).
#   The `enabled` master switch gates whether this config is consulted at
#   all — when off, runtime resolution falls back to global. This is the
#   safety mechanism: creating a record never changes behavior until an
#   admin explicitly enables it and sets the fields they want.
#   When an admin configures a domain, the config they see is the config
#   that runs — no invisible inheritance from install-level defaults.
#
# Scope Boundary:
#   Install-wide security posture (MFA, lockout, password_requirements,
#   active_sessions) is NOT overridable per domain. Those are infrastructure,
#   not tenant configuration.
#
# See: lib/onetime/auth_config.rb (AuthConfig, restrict_to logic)
#      etc/defaults/auth.defaults.yaml (install-level defaults)
#
module Onetime
  class CustomDomain < Familia::Horreum
    class SigninConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-signin-config'

      # Valid values for restrict_to — matches AuthConfig::RESTRICT_TO_VALUES
      RESTRICT_TO_VALUES = %w[password email_auth webauthn sso].freeze

      prefix :custom_domain__signin_config

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one signin config per domain.
      identifier_field :domain_id
      field :domain_id

      # Master switch: whether this per-domain signin config is active.
      # Non-nullable boolean, defaults to false.
      field :enabled

      # Non-nullable boolean overrides with conservative defaults (false).
      field :signin_enabled       # Override for AUTH_SIGNIN
      field :restrict_to          # Override for full.restrict_to (string or nil)
      field :email_auth_enabled   # Override for AUTH_EMAIL_AUTH_ENABLED
      field :sso_enabled          # Override for AUTH_SSO_ENABLED

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled            = false if enabled.nil?
        self.signin_enabled     = false if signin_enabled.nil?
        self.email_auth_enabled = false if email_auth_enabled.nil?
        self.sso_enabled        = false if sso_enabled.nil?
      end

      def enabled?
        enabled == true
      end

      def signin_enabled?
        signin_enabled == true
      end

      def email_auth_enabled?
        email_auth_enabled == true
      end

      def sso_enabled?
        sso_enabled == true
      end

      # Validate that all required fields are present.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?

        # restrict_to must be a known value when present
        if restrict_to && !RESTRICT_TO_VALUES.include?(restrict_to)
          errors << "restrict_to must be one of: #{RESTRICT_TO_VALUES.join(', ')}"
        end

        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
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

      class << self
        # Find signin config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::SigninConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Whether the domain's SigninConfig permits SSO as an auth method.
        #
        # Shared permission predicate so the display gate (config serializer)
        # and the runtime gate (omniauth_tenant hook) cannot diverge. Both
        # call sites consult this so the SSO button is never shown when the
        # auth route would reject, and never hidden when the route works.
        #
        # Master switch off / no config => permitted (defer to SsoConfig
        # credentials). Master switch on => sso_enabled? is authoritative.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [Boolean] true if SSO is permitted for the domain
        def sso_permitted_for?(domain_id)
          config = find_by_domain_id(domain_id)
          return true unless config&.enabled?

          config.sso_enabled?
        end

        # Resolve effective sign-in availability, combining the install-level
        # (global) capability with an optional per-domain override.
        #
        # AND semantics: an enabled per-domain config can only *narrow* the
        # global capability — it can never re-enable sign-in when the operator
        # has disabled it globally (AUTH_ENABLED / AUTH_SIGNIN). When no config
        # is enabled, the global value is authoritative.
        #
        # This is the single source of truth shared by the display gate
        # (Core::Views::Serializers::ConfigSerializer#resolve_signin) and the
        # runtime gate (Core::Controllers::Base#signin_enabled?), so the
        # rendered page and the POST handler cannot disagree about whether a
        # global kill switch is in effect.
        #
        # @param global [Boolean] install-level availability (auth.enabled && auth.signin)
        # @param config [SigninConfig, nil] the per-domain config, if any
        # @return [Boolean]
        def resolve_signin_enabled(global, config)
          global = global == true
          return global unless config&.enabled?

          global && config.signin_enabled?
        end

        # Check if a domain has signin config.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if signin config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new signin config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::SigninConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Signin config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          config.enabled            = attrs.key?(:enabled) ? attrs[:enabled] : false
          config.restrict_to        = attrs[:restrict_to] if attrs.key?(:restrict_to)

          # Convention: all boolean fields use conservative defaults (false).
          # The `enabled` master switch gates runtime consultation — creating
          # a record never changes behavior until explicitly enabled.
          config.signin_enabled     = attrs.key?(:signin_enabled) ? attrs[:signin_enabled] : false
          config.email_auth_enabled = attrs.key?(:email_auth_enabled) ? attrs[:email_auth_enabled] : false
          config.sso_enabled        = attrs.key?(:sso_enabled) ? attrs[:sso_enabled] : false

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          config.save

          config
        end

        # Delete signin config for a domain.
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

        # List all domain signin configs.
        #
        # @return [Array<CustomDomain::SigninConfig>] All configs (newest first)
        def all
          identifiers = instances.revrangeraw(0, -1)
          return [] if identifiers.empty?

          load_multi(identifiers).compact
        end

        # Count of domains with signin config.
        #
        # @return [Integer] Number of signin configs
        def count
          instances.size
        end
      end
    end
  end
end
