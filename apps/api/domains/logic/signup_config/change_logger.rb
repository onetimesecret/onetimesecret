# apps/api/domains/logic/signup_config/change_logger.rb
#
# frozen_string_literal: true

require_relative '../config_change_logger'

module DomainsAPI
  module Logic
    module SignupConfig
      # Audit logging for Domain Signup configuration changes.
      #
      # Shared machinery lives in DomainsAPI::Logic::ConfigChangeLogger.
      #
      # Unlike SsoConfig, SignupConfig has no sensitive credential fields, so
      # all configured fields are safe to log with their actual values.
      #
      # Events:
      #   - domain_signup_config_created: New signup configuration created
      #   - domain_signup_config_replaced: Existing signup configuration fully replaced (PUT)
      #   - domain_signup_config_updated: Signup configuration partially updated (PATCH)
      #   - domain_signup_config_deleted: Signup configuration removed
      #   - domain_signup_config_enabled: Signup validation enabled for domain
      #   - domain_signup_config_disabled: Signup validation disabled for domain
      #
      module ChangeLogger
        include DomainsAPI::Logic::ConfigChangeLogger

        # Fields safe to log with their actual values
        SAFE_FIELDS = %w[validation_strategy enabled allowed_signup_domains].freeze

        # Boolean fields: old value read via predicate, new value coerced
        BOOLEAN_FIELDS = %w[enabled].freeze

        # Log a Domain Signup audit event with structured data.
        #
        # @param event [String, Symbol] Event type (e.g., :domain_signup_config_created)
        # @param domain [Onetime::CustomDomain] Domain being modified
        # @param org [Onetime::Organization] Organization that owns the domain
        # @param actor [Onetime::Customer] User performing the action
        # @param validation_strategy [String] Validation strategy in effect
        # @param changes [Hash, nil] Field changes for update events
        # @param details [Hash, nil] Additional event-specific details
        # @return [void]
        def log_signup_change_event(event:, domain:, org:, actor:, validation_strategy:, changes: nil, details: nil)
          log_config_change_event(
            tag: 'DOMAIN_SIGNUP_CHANGE',
            event: event,
            domain: domain,
            org: org,
            actor: actor,
            extra: { validation_strategy: validation_strategy },
            changes: changes,
            details: details,
          )
        end

        # Compute changes between old config state and new parameters.
        #
        # @param old_config [Onetime::CustomDomain::SignupConfig] Existing configuration
        # @param new_params [Hash] New parameter values
        # @return [Hash] Changes hash with field names as keys
        def compute_signup_changes(old_config, new_params)
          compute_config_changes(
            old_config,
            new_params,
            safe_fields: SAFE_FIELDS,
            boolean_fields: BOOLEAN_FIELDS,
          )
        end
      end
    end
  end
end
