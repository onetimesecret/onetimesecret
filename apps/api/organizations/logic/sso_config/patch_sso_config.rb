# apps/api/organizations/logic/sso_config/patch_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'
require_relative 'serializers'
require_relative 'audit_logger'

module OrganizationAPI::Logic
  module SsoConfig
    # PATCH SSO Configuration (partial update)
    #
    # @api Partially updates the SSO configuration for an organization.
    #   Uses PATCH semantics: only provided fields are updated, empty values
    #   preserve existing data.
    #   Requires the requesting user to be an organization owner.
    #
    # Request body:
    # - provider_type: Required. One of: oidc, entra_id, google, github
    # - client_id: Required. OAuth client ID
    # - client_secret: Optional for update (preserves existing if empty)
    # - tenant_id: Required for entra_id provider (preserves existing if empty)
    # - issuer: Required for oidc provider (preserves existing if empty)
    # - display_name: Optional. Human-readable name (preserves existing if empty)
    # - allowed_domains: Optional. Array of allowed email domains
    # - enabled: Optional. Boolean to enable/disable SSO (default: false)
    #
    # Response includes the updated config with masked client_secret_masked.
    #
    class PatchSsoConfig < OrganizationAPI::Logic::Base
      include Serializers
      include AuditLogger

      VALID_PROVIDER_TYPES = Onetime::OrgSsoConfig::PROVIDER_TYPES.freeze

      attr_reader :organization, :sso_config, :existing_config

      def process_params
        @extid           = sanitize_identifier(params['extid'])
        @provider_type   = sanitize_plain_text(params['provider_type'])
        @display_name    = sanitize_plain_text(params['display_name'])
        @client_id       = params['client_id'].to_s.strip
        @client_secret   = params['client_secret'].to_s.strip
        @tenant_id       = sanitize_plain_text(params['tenant_id'])
        @issuer          = sanitize_url(params['issuer'])
        @allowed_domains = parse_allowed_domains(params['allowed_domains'])
        @enabled         = parse_boolean(params['enabled'])
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate extid parameter
        raise_form_error('Organization ID required', field: :extid, error_type: :missing) if @extid.to_s.empty?

        # Load organization
        @organization = load_organization(@extid)

        # Verify user is owner (SSO config is sensitive)
        verify_organization_owner(@organization)

        # Check if config already exists
        @existing_config = Onetime::OrgSsoConfig.find_by_org_id(@organization.objid)

        # Validate provider_type
        validate_provider_type

        # Validate client credentials
        validate_client_credentials

        # Validate provider-specific fields
        validate_provider_specific_fields
      end

      def process
        OT.ld "[PatchSsoConfig] Patching SSO config for organization #{@extid} by user #{cust.extid}"

        # Track enabled state change for audit
        was_enabled = @existing_config&.enabled?

        if @existing_config
          # Compute changes before updating
          changes = compute_sso_changes(@existing_config, params)
          update_existing_config
          log_sso_audit_event(
            event: :sso_config_updated,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
            changes: changes,
          )
        else
          create_new_config
          log_sso_audit_event(
            event: :sso_config_created,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        end

        # Log enabled state change if it occurred
        log_enabled_state_change(was_enabled, @enabled)

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          record: serialize_sso_config(@sso_config),
        }
      end

      def form_fields
        {
          extid: @extid,
          provider_type: @provider_type,
          display_name: @display_name,
          tenant_id: @tenant_id,
          issuer: @issuer,
          allowed_domains: @allowed_domains,
          enabled: @enabled,
        }
      end

      private

      def validate_provider_type
        raise_form_error('Provider type is required', field: :provider_type, error_type: :missing) if @provider_type.to_s.empty?

        return if VALID_PROVIDER_TYPES.include?(@provider_type)

        raise_form_error(
          "Invalid provider type. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
          field: :provider_type,
          error_type: :invalid,
        )
      end

      def validate_client_credentials
        raise_form_error('Client ID is required', field: :client_id, error_type: :missing) if @client_id.to_s.empty?

        # client_secret is required for new configs, optional for updates (preserves existing)
        if @existing_config.nil? && @client_secret.to_s.empty?
          raise_form_error('Client secret is required', field: :client_secret, error_type: :missing)
        end
      end

      def validate_provider_specific_fields
        case @provider_type
        when 'oidc'
          # For PATCH: require issuer if creating new config or if existing config has no issuer
          missing_issuer = @issuer.to_s.empty? &&
                           (@existing_config.nil? || @existing_config.issuer.to_s.empty?)
          if missing_issuer
            raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing)
          end
        when 'entra_id'
          # For PATCH: require tenant_id if creating new config or if existing config has no tenant_id
          missing_tenant = @tenant_id.to_s.empty? &&
                           (@existing_config.nil? || @existing_config.tenant_id.to_s.empty?)
          if missing_tenant
            raise_form_error('Tenant ID is required for Entra ID provider', field: :tenant_id, error_type: :missing)
          end
        end
      end

      def create_new_config
        @sso_config = Onetime::OrgSsoConfig.create!(
          org_id: @organization.objid,
          provider_type: @provider_type,
          display_name: @display_name,
          client_id: @client_id,
          client_secret: @client_secret,
          tenant_id: @tenant_id,
          issuer: @issuer,
          allowed_domains: @allowed_domains,
          enabled: @enabled,
        )
      end

      # Updates an existing SSO config with PATCH semantics.
      #
      # PATCH Semantics:
      # - Most optional fields (display_name, tenant_id, issuer, client_secret)
      #   are preserved when empty/omitted, allowing partial updates.
      # - Provider-specific fields are preserved on provider switch. For example,
      #   switching from entra_id to google preserves tenant_id, and switching
      #   from oidc to entra_id preserves issuer. This is intentional behavior
      #   that allows reverting to the previous provider without re-entering
      #   credentials.
      #
      # Exception - allowed_domains uses PUT semantics:
      # - An empty array explicitly clears all existing domains
      # - Omitting the field results in an empty array (not preservation)
      # - This differs from other optional fields to support explicit domain clearing
      #
      def update_existing_config
        @sso_config = @existing_config

        # PATCH semantics: only update fields that are provided (non-empty)
        @sso_config.provider_type = @provider_type
        @sso_config.display_name  = @display_name unless @display_name.to_s.empty?
        @sso_config.client_id     = @client_id
        @sso_config.tenant_id     = @tenant_id unless @tenant_id.to_s.empty?
        @sso_config.issuer        = @issuer unless @issuer.to_s.empty?
        @sso_config.enabled       = @enabled.to_s

        # Only update client_secret if provided (preserves existing otherwise)
        @sso_config.client_secret = @client_secret unless @client_secret.to_s.empty?

        # allowed_domains uses PUT semantics: always replaces (see comment above)
        @sso_config.allowed_domains = @allowed_domains

        # Update timestamp for partial update
        @sso_config.updated = Familia.now.to_i

        @sso_config.save
      end

      def parse_allowed_domains(value)
        return [] if value.nil?
        return value if value.is_a?(Array)

        # Handle comma-separated string
        if value.is_a?(String)
          value.split(',').map { it.strip.downcase }.reject(&:empty?)
        else
          []
        end
      end

      def parse_boolean(value)
        case value
        when true, 'true', '1', 1
          true
        else
          false
        end
      end

      def sanitize_url(value)
        return '' if value.nil?

        url = value.to_s.strip
        # Basic URL validation - must start with https:// for security
        return '' unless url.start_with?('https://')

        url
      end

      # Log enabled/disabled state change if it occurred.
      #
      # @param was_enabled [Boolean, nil] Previous enabled state (nil if new config)
      # @param is_enabled [Boolean] New enabled state
      def log_enabled_state_change(was_enabled, is_enabled)
        # Skip if no change (both false, or both true)
        return if was_enabled == is_enabled

        # Log when SSO is enabled (new config or was disabled)
        if is_enabled && (was_enabled.nil? || was_enabled == false)
          log_sso_audit_event(
            event: :sso_config_enabled,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        elsif was_enabled == true && !is_enabled
          log_sso_audit_event(
            event: :sso_config_disabled,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        end
      end
    end
  end
end
