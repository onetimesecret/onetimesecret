# lib/onetime/models/org_sso_config.rb
#
# frozen_string_literal: true

module Onetime
  # Per-Organization SSO Configuration
  #
  # Stores SSO/OIDC credentials for organizations that manage their own
  # identity provider connections. This enables multi-tenant SSO where each
  # organization can configure their own Entra ID, Google Workspace, or
  # generic OIDC provider without requiring server environment variables.
  #
  # Design Decisions:
  #
  # 1. One-to-One with Organization: Each organization has at most one SSO
  #    config. The org_id field is the identifier, ensuring uniqueness via
  #    Familia's key structure (org_sso_config:<org_id>).
  #
  # 2. Encrypted Credentials: client_id and client_secret are stored using
  #    Familia's encrypted_field feature, providing at-rest encryption with
  #    the application's configured encryption key.
  #
  # 3. Provider Types: Supports 'oidc' (generic), 'entra_id', 'google', and
  #    'github'. Each has slightly different OmniAuth options (e.g., Entra
  #    requires tenant_id, OIDC requires issuer for discovery).
  #
  # 4. Domain Allowlist: The allowed_domains list restricts which email
  #    domains can authenticate via this SSO config. Empty list means no
  #    restriction (any domain allowed).
  #
  # 5. class_hashkey :configs_by_org: Provides O(1) lookup from org_id to
  #    config identifier, avoiding a full scan when checking if an org has
  #    SSO configured.
  #
  # Redis Key Structure:
  #   - Individual config: org_sso_config:<org_id> (hash)
  #   - Lookup index: org_sso_config:configs_by_org (hash: org_id -> org_id)
  #   - Instance tracking: org_sso_config:instances (sorted set)
  #
  # Usage:
  #   config = OrgSsoConfig.find_by_org_id(org.objid)
  #   options = config.to_omniauth_options if config&.enabled?
  #
  class OrgSsoConfig < Familia::Horreum
    include Familia::Features::Autoloader

    SCHEMA = 'models/org-sso-config'

    # Supported SSO provider types. Each maps to a specific OmniAuth strategy:
    #   - oidc: omniauth-openid-connect (generic OIDC with discovery)
    #   - entra_id: omniauth-entra-id (Microsoft Entra ID / Azure AD)
    #   - google: omniauth-google-oauth2 (Google Workspace)
    #   - github: omniauth-github (GitHub OAuth)
    PROVIDER_TYPES = %w[oidc entra_id google github].freeze

    prefix :org_sso_config

    # NOTE: safe_dump_fields feature requires per-model feature file setup.
    # For Phase 1, we skip it since SSO configs contain sensitive credentials
    # that should never be serialized for API responses. If safe_dump is needed
    # later, create lib/onetime/models/org_sso_config/features/safe_dump_fields.rb
    #
    # NOTE: We intentionally do NOT use feature :object_identifier here because
    # we want org_id (the associated Organization's objid) as our identifier,
    # not a separate auto-generated UUID. This creates a 1:1 relationship where
    # the Redis key becomes org_sso_config:<org_id>, guaranteeing uniqueness.
    feature :encrypted_fields

    # org_id is the Organization's objid, used as our identifier.
    # This field MUST be set when creating a config.
    identifier_field :org_id
    field :org_id

    # Core configuration fields
    field :provider_type   # One of PROVIDER_TYPES
    field :enabled         # Boolean string ('true'/'false') - SSO active for this org
    field :display_name    # Human-readable name for UI (e.g., "Acme Corp SSO")

    # Provider-specific fields (not all used by every provider)
    field :tenant_id       # Entra ID: Azure AD tenant ID
    field :issuer          # OIDC: Issuer URL for discovery endpoint

    # Encrypted credential storage - these contain sensitive OAuth secrets
    # that should never be logged or exposed in API responses.
    # Uses Familia's encrypted_field feature with AES-256-GCM.
    encrypted_field :client_id
    encrypted_field :client_secret

    # Domain allowlist stored as JSON array string.
    # Validates that authenticating users have email domains in this list.
    # Empty or nil means no domain restriction.
    field :allowed_domains_json

    # O(1) lookup index: org_id -> org_id (value is same as key since org_id
    # is the identifier). This enables fast existence checks without loading
    # the full config.
    #
    # Example Redis structure:
    #   HSET org_sso_config:configs_by_org <org_id> <org_id>
    class_hashkey :configs_by_org

    def init
      self.enabled       ||= 'false'
      self.provider_type ||= 'oidc'
    end

    # Check if SSO is enabled for this organization.
    # Handles string/boolean coercion since Redis stores strings.
    #
    # @return [Boolean] true if SSO is active and should be used
    def enabled?
      enabled.to_s == 'true'
    end

    # Enable SSO for this organization.
    # @return [void]
    def enable!
      self.enabled = 'true'
      save
    end

    # Disable SSO for this organization.
    # @return [void]
    def disable!
      self.enabled = 'false'
      save
    end

    # Get the list of allowed email domains.
    # Returns empty array if no restrictions configured.
    #
    # @return [Array<String>] Lowercase domain names (e.g., ['acme.com', 'acme.io'])
    def allowed_domains
      return [] if allowed_domains_json.to_s.empty?

      JSON.parse(allowed_domains_json)
    rescue JSON::ParserError
      []
    end

    # Set the list of allowed email domains.
    # Normalizes domains to lowercase and removes duplicates.
    #
    # @param domains [Array<String>] Domain names to allow
    # @return [void]
    def allowed_domains=(domains)
      normalized                = Array(domains).map { it.to_s.strip.downcase }.uniq.reject(&:empty?)
      self.allowed_domains_json = normalized.empty? ? nil : JSON.generate(normalized)
    end

    # Validate an email address against the allowed domains list.
    # Returns true if:
    #   - No domain restrictions configured (allowed_domains is empty), OR
    #   - Email domain matches one of the allowed domains
    #
    # @param email [String] Email address to validate
    # @return [Boolean] true if email domain is allowed
    def valid_email_domain?(email)
      domains = allowed_domains
      return true if domains.empty?

      email_domain = email.to_s.split('@').last&.downcase
      return false if email_domain.nil? || email_domain.empty?

      domains.include?(email_domain)
    end

    # Generate OmniAuth strategy options for runtime injection.
    # Returns a provider-specific hash suitable for passing to
    # OmniAuth::Strategies::OpenIDConnect or provider-specific strategies.
    #
    # The returned options use the org_id as the strategy name, creating
    # unique callback routes per organization (e.g., /auth/sso/<org_id>/callback).
    #
    # @return [Hash] OmniAuth provider options
    # @raise [Onetime::Problem] if provider_type is unsupported
    def to_omniauth_options
      case provider_type
      when 'oidc'
        build_oidc_options
      when 'entra_id'
        build_entra_id_options
      when 'google'
        build_google_options
      when 'github'
        build_github_options
      else
        raise Onetime::Problem, "Unsupported SSO provider type: #{provider_type}"
      end
    end

    # Load the associated Organization record.
    #
    # @return [Organization, nil] The organization or nil if not found
    def organization
      Onetime::Organization.load(org_id)
    end

    # Validate that all required fields are present for the provider type.
    # Does not validate credential correctness, only presence.
    #
    # @return [Array<String>] List of validation error messages (empty if valid)
    def validation_errors
      errors = []

      errors << 'org_id is required' if org_id.to_s.empty?
      errors << 'provider_type is required' if provider_type.to_s.empty?
      errors << "provider_type must be one of: #{PROVIDER_TYPES.join(', ')}" unless PROVIDER_TYPES.include?(provider_type)

      # Reveal encrypted values for presence check (returns nil if not set)
      client_id_val     = begin
                        client_id&.reveal { it }
      rescue StandardError
                        nil
      end
      client_secret_val = begin
                            client_secret&.reveal { it }
      rescue StandardError
                            nil
      end

      errors << 'client_id is required' if client_id_val.to_s.empty?
      errors << 'client_secret is required' if client_secret_val.to_s.empty?

      # Provider-specific validations
      case provider_type
      when 'oidc'
        errors << 'issuer is required for OIDC provider' if issuer.to_s.empty?
      when 'entra_id'
        errors << 'tenant_id is required for Entra ID provider' if tenant_id.to_s.empty?
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
      # Find SSO config by organization ID.
      # Uses the class_hashkey index for O(1) lookup.
      #
      # @param org_id [String] Organization objid
      # @return [OrgSsoConfig, nil] The config or nil if not found
      def find_by_org_id(org_id)
        return nil if org_id.to_s.empty?

        # Check index first (fast path)
        return nil unless configs_by_org.member?(org_id)

        # Load the config using org_id as identifier
        load(org_id)
      rescue Onetime::RecordNotFound
        nil
      end

      # Check if an organization has SSO configured.
      # O(1) operation using the hash index.
      #
      # @param org_id [String] Organization objid
      # @return [Boolean] true if SSO config exists for this org
      def exists_for_org?(org_id)
        return false if org_id.to_s.empty?

        configs_by_org.member?(org_id)
      end

      # Create a new SSO config for an organization.
      # Validates that no config already exists for the org.
      #
      # @param org_id [String] Organization objid
      # @param attrs [Hash] Configuration attributes
      # @option attrs [String] :provider_type One of PROVIDER_TYPES
      # @option attrs [String] :display_name Human-readable name
      # @option attrs [String] :client_id OAuth client ID
      # @option attrs [String] :client_secret OAuth client secret
      # @option attrs [String] :tenant_id Entra ID tenant (if applicable)
      # @option attrs [String] :issuer OIDC issuer URL (if applicable)
      # @option attrs [Array<String>] :allowed_domains Email domain allowlist
      # @option attrs [Boolean] :enabled Whether SSO is active (default: false)
      # @return [OrgSsoConfig] The created config
      # @raise [Onetime::Problem] if config already exists for org
      def create!(org_id:, **attrs)
        raise Onetime::Problem, 'org_id is required' if org_id.to_s.empty?
        raise Onetime::Problem, 'SSO config already exists for this organization' if exists_for_org?(org_id)

        config = new(org_id: org_id)

        # Set simple fields
        config.provider_type = attrs[:provider_type] if attrs.key?(:provider_type)
        config.display_name  = attrs[:display_name] if attrs.key?(:display_name)
        config.tenant_id     = attrs[:tenant_id] if attrs.key?(:tenant_id)
        config.issuer        = attrs[:issuer] if attrs.key?(:issuer)
        config.enabled       = attrs[:enabled].to_s if attrs.key?(:enabled)

        # Set encrypted fields
        config.client_id     = attrs[:client_id] if attrs.key?(:client_id)
        config.client_secret = attrs[:client_secret] if attrs.key?(:client_secret)

        # Set allowed domains (handles array conversion)
        config.allowed_domains = attrs[:allowed_domains] if attrs.key?(:allowed_domains)

        # Atomic save + index update using Redis MULTI/EXEC
        # Prevents race condition where config exists but index doesn't (or vice versa)
        Familia.redis.multi do |txn|
          # Save config fields to Redis hash
          txn.hmset(config.rediskey, *config.to_h.flatten)
          # Add to instances sorted set for enumeration
          txn.zadd(instances.rediskey, Time.now.to_f, org_id)
          # Update the lookup index
          txn.hset(configs_by_org.rediskey, org_id, org_id)
        end

        config
      end

      # Delete SSO config for an organization.
      # Removes from both the config storage and the lookup index atomically.
      #
      # @param org_id [String] Organization objid
      # @return [Boolean] true if deleted, false if not found
      def delete_for_org!(org_id)
        return false if org_id.to_s.empty?

        config = find_by_org_id(org_id)
        return false unless config

        # Atomic delete using Redis MULTI/EXEC
        # Prevents race condition where index is removed but config remains (or vice versa)
        Familia.redis.multi do |txn|
          # Delete the config hash
          txn.del(config.rediskey)
          # Remove from instances sorted set
          txn.zrem(instances.rediskey, org_id)
          # Remove from lookup index
          txn.hdel(configs_by_org.rediskey, org_id)
        end

        true
      end

      # List all configured SSO providers.
      # Returns configs sorted by creation time (newest first).
      #
      # @return [Array<OrgSsoConfig>] All SSO configs
      def all
        instances.revrangeraw(0, -1).filter_map do |identifier|
          load(identifier)
        rescue Onetime::RecordNotFound
          nil
        end
      end

      # Count of organizations with SSO configured.
      #
      # @return [Integer] Number of SSO configs
      def count
        configs_by_org.size
      end
    end

    private

    # Build OIDC (generic OpenID Connect) options.
    # Uses issuer discovery to auto-configure endpoints.
    def build_oidc_options
      {
        strategy: :openid_connect,
        name: org_id,
        scope: [:openid, :email, :profile],
        response_type: :code,
        issuer: issuer,
        discovery: true,
        pkce: true,
        client_options: {
          identifier: client_id&.reveal { it },
          secret: client_secret&.reveal { it },
        },
      }
    end

    # Build Entra ID (Microsoft Azure AD) options.
    # Requires tenant_id for multi-tenant Azure apps.
    def build_entra_id_options
      {
        strategy: :entra_id,
        name: org_id,
        client_id: client_id&.reveal { it },
        client_secret: client_secret&.reveal { it },
        tenant_id: tenant_id,
        scope: 'openid profile email',
      }
    end

    # Build Google OAuth2 options.
    # Uses Google's OAuth2 endpoints with profile/email scopes.
    def build_google_options
      {
        strategy: :google_oauth2,
        name: org_id,
        client_id: client_id&.reveal { it },
        client_secret: client_secret&.reveal { it },
        scope: 'openid,email,profile',
        prompt: 'select_account',
      }
    end

    # Build GitHub OAuth options.
    # Uses user:email scope to access email for account matching.
    def build_github_options
      {
        strategy: :github,
        name: org_id,
        client_id: client_id&.reveal { it },
        client_secret: client_secret&.reveal { it },
        scope: 'user:email',
      }
    end
  end
end
