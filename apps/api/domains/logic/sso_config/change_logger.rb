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
      #   - domain_sso_name_id_format_changed: a saml record's NameID policy
      #     changed (WARN level — see #log_name_id_format_change)
      #
      module ChangeLogger
        include DomainsAPI::Logic::ConfigChangeLogger

        # Fields that contain sensitive data and must never be logged.
        #
        # The SAML trio (#4450) is not secret, but it is listed here anyway:
        # these fields are logged as `changed: true` with no value, which is
        # the right audit shape for a trust anchor (a multi-line certificate
        # has no business in a log line) and the only shape available for an
        # encrypted_field — the safe-field path reads the old value straight
        # off the record, where it is a ConcealedString.
        SENSITIVE_FIELDS = %w[client_id client_secret idp_sso_service_url idp_entity_id idp_cert name_id_format callback_origins].freeze

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
        # @param level [Symbol] :info (default) or :warn
        # @return [void]
        def log_sso_change_event(event:, domain:, org:, actor:, provider_type:, changes: nil, details: nil, level: :info)
          log_config_change_event(
            tag: 'DOMAIN_SSO_CHANGE',
            event: event,
            domain: domain,
            org: org,
            actor: actor,
            extra: { provider_type: provider_type },
            changes: changes,
            details: details,
            level: level,
          )
        end

        # A saml record's NameID policy changed. Every SAML identity from a
        # tenant is keyed on (provider, issuer, NameID) — tenant records have
        # no uid attribute — so a persistent → emailAddress switch (or the
        # reverse, or a PUT that omits the field and so restores persistent)
        # makes every existing identity a stranger: the next sign-in from
        # each user provisions or links afresh instead of resuming. The
        # domain SSO API has no warning channel in its response shape, so
        # this is recorded at WARN with the audit payload (formats
        # deliberately not logged: name_id_format is a SENSITIVE_FIELDS
        # entry, and the fact of the change is what matters).
        #
        # Caller decides whether the change happened (the stored value is
        # encrypted and may be unreadable; SamlFields#stored_name_id_format).
        #
        # @param domain [Onetime::CustomDomain]
        # @param org [Onetime::Organization]
        # @param actor [Onetime::Customer]
        # @param was_enabled [Boolean] whether the record was live before
        #   the change (a live record is the one with identities behind it)
        # @return [void]
        def log_name_id_format_change(domain:, org:, actor:, was_enabled:)
          log_sso_change_event(
            event: :domain_sso_name_id_format_changed,
            domain: domain,
            org: org,
            actor: actor,
            provider_type: 'saml',
            details: { was_enabled: was_enabled == true, identities_rekeyed: true },
            level: :warn,
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
