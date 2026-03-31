# lib/onetime/models/custom_domain/sso_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::SsoConfig - Per-domain SSO credential storage
#
# This model stores SSO credentials bound to a specific CustomDomain.
# This enables multi-IdP configurations where different domains owned
# by the same organization can use different identity providers.
#
# Use Cases:
#   - Regional compliance: secrets.acme.eu uses Google Workspace, secrets.acme.com uses Entra ID
#   - Gradual rollout: enable SSO on one domain before expanding to others
#   - Subsidiary isolation: different business units use different IdPs
#
# Credential Binding:
#   Credentials are encrypted with AAD (Additional Authenticated Data) bound
#   to domain_id, preventing credential swapping attacks between domains.
#
# See: apps/web/auth/config/hooks/omniauth_tenant.rb (tenant resolution)
#
module Onetime
  class CustomDomain < Familia::Horreum
    class SsoConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-sso-config'

      # Supported SSO provider types
      PROVIDER_TYPES = %w[oidc entra_id google github].freeze

      # Provider metadata for UI filtering logic
      #
      # :requires_domain_filter - When true, UI should show domain filter config
      #   prominently because the IdP doesn't restrict access by default.
      #   When false, IdP controls access via user/app assignment.
      #
      # :idp_controls_access - When true, the IdP is the source of truth for
      #   which users can access the app. When false, anyone with valid IdP
      #   credentials could potentially authenticate.
      #
      PROVIDER_METADATA = {
        'oidc' => {
          requires_domain_filter: true,
          idp_controls_access: false,
          description: 'Generic OpenID Connect provider - domain filtering recommended',
        },
        'entra_id' => {
          requires_domain_filter: false,
          idp_controls_access: true,
          description: 'Microsoft Entra ID - access controlled via Azure app assignment',
        },
        'google' => {
          requires_domain_filter: true,
          idp_controls_access: false,
          description: 'Google Workspace - domain filtering recommended for enterprise',
        },
        'github' => {
          requires_domain_filter: true,
          idp_controls_access: false,
          description: 'GitHub OAuth - domain filtering recommended',
        },
      }.freeze

      prefix :custom_domain__sso_config

      feature :encrypted_fields

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one SSO config per domain.
      identifier_field :domain_id
      field :domain_id

      # Core configuration fields
      field :provider_type   # One of PROVIDER_TYPES
      field :enabled         # Boolean string ('true'/'false')
      field :display_name    # Human-readable name for UI

      # Provider-specific fields
      #
      # Required fields vary by provider_type:
      #   - entra_id: requires tenant_id
      #   - oidc:     requires issuer
      #   - google:   neither (uses well-known Google endpoints)
      #   - github:   neither (uses well-known GitHub endpoints)
      #
      # Universal required fields (all providers):
      #   - client_id, client_secret, display_name, provider_type
      #
      # See: validation_errors method for enforcement
      #
      field :tenant_id       # Entra ID: Azure AD tenant ID (required for entra_id only)
      field :issuer          # OIDC: Issuer URL for discovery (required for oidc only)

      # Encrypted credential storage with domain-bound AAD
      encrypted_field :client_id, aad_fields: [:domain_id]
      encrypted_field :client_secret, aad_fields: [:domain_id]

      # Domain allowlist (JSON array string)
      field :allowed_domains_json

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled       ||= 'false'
        self.provider_type ||= 'oidc'
      end

      # Check if SSO is enabled for this domain.
      #
      # @return [Boolean] true if SSO is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Returns metadata for the current provider type.
      #
      # @return [Hash] Provider metadata
      def provider_metadata
        PROVIDER_METADATA.fetch(provider_type, {})
      end

      # Whether domain filtering is recommended for this provider.
      #
      # @return [Boolean]
      def requires_domain_filter?
        provider_metadata.fetch(:requires_domain_filter, false)
      end

      # Whether the IdP controls access via user/app assignment.
      #
      # @return [Boolean]
      def idp_controls_access?
        provider_metadata.fetch(:idp_controls_access, true)
      end

      # Enable SSO for this domain.
      # @return [void]
      def enable!
        self.enabled = 'true'
        save
      end

      # Disable SSO for this domain.
      # @return [void]
      def disable!
        self.enabled = 'false'
        save
      end

      # Get the list of allowed email domains.
      #
      # @return [Array<String>] Lowercase domain names
      def allowed_domains
        return [] if allowed_domains_json.to_s.empty?

        JSON.parse(allowed_domains_json)
      rescue JSON::ParserError
        []
      end

      # Set the list of allowed email domains.
      #
      # Validates each domain using PublicSuffix to ensure it has a valid TLD.
      # Supports internationalized domain names (IDN).
      #
      # @param domains [Array<String>] Domain names to allow
      # @return [void]
      # @raise [Onetime::Problem] if any domain is invalid
      def allowed_domains=(domains)
        normalized = Array(domains).map { it.to_s.strip.downcase }.uniq.reject(&:empty?)

        # Validate each domain using PublicSuffix (handles IDN, validates TLD)
        normalized.each do |domain|
            Utils::DomainParser.cached_parse(domain)
        rescue PublicSuffix::Error => ex
            raise Onetime::Problem, "Invalid domain: #{domain} (#{ex.message})"
        end

        self.allowed_domains_json = normalized.empty? ? nil : JSON.generate(normalized)
      end

      # Validate an email address against the allowed domains list.
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

      # Validate that all required fields are present for the provider type.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?
        errors << 'provider_type is required' if provider_type.to_s.empty?
        errors << "provider_type must be one of: #{PROVIDER_TYPES.join(', ')}" unless PROVIDER_TYPES.include?(provider_type)

        # Check encrypted values for presence
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

        # Provider-specific field requirements:
        #
        #   | provider_type | tenant_id | issuer |
        #   |---------------|-----------|--------|
        #   | entra_id      | required  | -      |
        #   | oidc          | -         | required |
        #   | google        | -         | -      |
        #   | github        | -         | -      |
        #
        # Google and GitHub use well-known OAuth endpoints, so neither
        # tenant_id nor issuer is needed. Universal fields (client_id,
        # client_secret, display_name) are validated above.
        #
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
        # Returns provider metadata for all supported providers.
        #
        # @return [Hash] Provider type => metadata hash
        def provider_metadata
          PROVIDER_METADATA
        end

        # Returns metadata for a specific provider type.
        #
        # @param provider_type [String] One of PROVIDER_TYPES
        # @return [Hash] Provider metadata or empty hash
        def metadata_for(provider_type)
          PROVIDER_METADATA.fetch(provider_type.to_s, {})
        end

        # Find SSO config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::SsoConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Check if a domain has SSO configured.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if SSO config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new SSO config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::SsoConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'SSO config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          # Set simple fields
          config.provider_type = attrs[:provider_type] if attrs.key?(:provider_type)
          config.display_name  = attrs[:display_name] if attrs.key?(:display_name)
          config.tenant_id     = attrs[:tenant_id] if attrs.key?(:tenant_id)
          config.issuer        = attrs[:issuer] if attrs.key?(:issuer)
          config.enabled       = attrs[:enabled].to_s if attrs.key?(:enabled)

          # Set encrypted fields
          config.client_id     = attrs[:client_id] if attrs.key?(:client_id)
          config.client_secret = attrs[:client_secret] if attrs.key?(:client_secret)

          # Set allowed domains
          config.allowed_domains = attrs[:allowed_domains] if attrs.key?(:allowed_domains)

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          # Save using Horreum's built-in method
          config.save

          config
        end

        # Delete SSO config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if deleted, false if not found
        def delete_for_domain!(domain_id)
          return false if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          return false unless config

          # Use Horreum's destroy! which handles main key + instances zset
          config.destroy!

          true
        end

        # List all domain SSO configs.
        #
        # @return [Array<CustomDomain::SsoConfig>] All configs (newest first)
        def all
          instances.revrangeraw(0, -1).filter_map do |identifier|
            load(identifier)
          rescue Onetime::RecordNotFound
            nil
          end
        end

        # Count of domains with SSO configured.
        #
        # @return [Integer] Number of SSO configs
        def count
          instances.size
        end
      end

      private

      # Build OIDC options (uses domain_id as strategy name)
      def build_oidc_options
        {
          strategy: :openid_connect,
          name: domain_id,
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

      # Build Entra ID options
      def build_entra_id_options
        {
          strategy: :entra_id,
          name: domain_id,
          client_id: client_id&.reveal { it },
          client_secret: client_secret&.reveal { it },
          tenant_id: tenant_id,
          scope: 'openid profile email',
        }
      end

      # Build Google OAuth2 options
      def build_google_options
        {
          strategy: :google_oauth2,
          name: domain_id,
          client_id: client_id&.reveal { it },
          client_secret: client_secret&.reveal { it },
          scope: 'openid,email,profile',
          prompt: 'select_account',
        }
      end

      # Build GitHub OAuth options
      def build_github_options
        {
          strategy: :github,
          name: domain_id,
          client_id: client_id&.reveal { it },
          client_secret: client_secret&.reveal { it },
          scope: 'user:email',
        }
      end
    end
  end
end
