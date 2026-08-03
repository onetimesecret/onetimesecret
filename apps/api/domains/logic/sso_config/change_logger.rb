# apps/api/domains/logic/sso_config/change_logger.rb
#
# frozen_string_literal: true

require_relative '../config_change_logger'

module DomainsAPI
  module Logic
    module SsoConfig
      # Audit logging for Domain SSO configuration changes.
      #
      # Shared machinery lives in DomainsAPI::Logic::ConfigChangeLogger.
      #
      # SECURITY: Sensitive fields (client_id, client_secret) are NEVER logged.
      # For credential changes, we log only that the field changed, not its value.
      #
      # Events:
      #   - domain_sso_config_created: New SSO configuration created
      #   - domain_sso_config_replaced: Existing SSO configuration fully replaced (PUT)
      #   - domain_sso_config_updated: SSO configuration partially updated (PATCH)
      #   - domain_sso_config_deleted: SSO configuration removed
      #   - domain_sso_config_enabled: SSO enabled for domain
      #   - domain_sso_config_disabled: SSO disabled for domain
      #
      module ChangeLogger
        include DomainsAPI::Logic::ConfigChangeLogger

        # Fields that contain sensitive data and must never be logged
        SENSITIVE_FIELDS = %w[client_id client_secret].freeze

        # Fields safe to log with their actual values
        SAFE_FIELDS = %w[provider_type display_name enabled enforce_sso_only grant_org_scope tenant_id issuer allowed_domains].freeze

        # Boolean fields: old value read via predicate, new value coerced
        BOOLEAN_FIELDS = %w[enabled enforce_sso_only grant_org_scope].freeze

        # Log a Domain SSO audit event with structured data.
        #
        # @param event [String, Symbol] Event type (e.g., :domain_sso_config_created)
        # @param domain [Onetime::CustomDomain] Domain being modified
        # @param org [Onetime::Organization] Organization that owns the domain
        # @param actor [Onetime::Customer] User performing the action
        # @param provider_type [String] SSO provider type
        # @param changes [Hash, nil] Field changes for update events
        # @param details [Hash, nil] Additional event-specific details
        # @return [void]
        def log_sso_change_event(event:, domain:, org:, actor:, provider_type:, changes: nil, details: nil)
          log_config_change_event(
            tag: 'DOMAIN_SSO_CHANGE',
            event: event,
            domain: domain,
            org: org,
            actor: actor,
            extra: { provider_type: provider_type },
            changes: changes,
            details: details,
          )
        end

        # Compute changes between old config state and new parameters.
        #
        # @param old_config [Onetime::CustomDomain::SsoConfig] Existing configuration
        # @param new_params [Hash] New parameter values
        # @return [Hash] Changes hash with field names as keys
        def compute_sso_changes(old_config, new_params)
          compute_config_changes(
            old_config,
            new_params,
            safe_fields: SAFE_FIELDS,
            sensitive_fields: SENSITIVE_FIELDS,
            boolean_fields: BOOLEAN_FIELDS,
          )
        end
      end
    end
  end
end
