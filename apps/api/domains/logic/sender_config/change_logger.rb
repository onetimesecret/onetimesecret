# apps/api/domains/logic/sender_config/change_logger.rb
#
# frozen_string_literal: true

require_relative '../config_change_logger'

module DomainsAPI
  module Logic
    module SenderConfig
      # Audit logging for Domain Sender Configuration changes.
      #
      # Shared machinery lives in DomainsAPI::Logic::ConfigChangeLogger.
      #
      # SECURITY: Sensitive fields (api_key) are NEVER logged.
      # For credential changes, we log only that the field changed, not its value.
      #
      # Events:
      #   - domain_sender_config_created: New sender configuration created
      #   - domain_sender_config_replaced: Existing config fully replaced (PUT)
      #   - domain_sender_config_updated: Config partially updated (PATCH)
      #   - domain_sender_config_deleted: Config removed
      #   - domain_sender_config_enabled: Sender config enabled for domain
      #   - domain_sender_config_disabled: Sender config disabled for domain
      #
      module ChangeLogger
        include DomainsAPI::Logic::ConfigChangeLogger

        # Fields that contain sensitive data and must never be logged
        SENSITIVE_FIELDS = %w[api_key].freeze

        # Fields safe to log with their actual values
        SAFE_FIELDS = %w[provider from_name from_address reply_to enabled].freeze

        # Boolean fields: old value read via predicate, new value coerced
        BOOLEAN_FIELDS = %w[enabled].freeze

        # Log a Domain Sender Config audit event with structured data.
        #
        # @param event [String, Symbol] Event type (e.g., :domain_sender_config_created)
        # @param domain [Onetime::CustomDomain] Domain being modified
        # @param org [Onetime::Organization] Organization that owns the domain
        # @param actor [Onetime::Customer] User performing the action
        # @param provider [String, nil] Mail provider type (optional, resolved from installation config)
        # @param changes [Hash, nil] Field changes for update events
        # @param details [Hash, nil] Additional event-specific details
        # @param timestamp [Integer] Unix timestamp; defaults to Time.now.to_i.
        #   Pass explicitly to ensure multiple audit events in one request share
        #   the same timestamp.
        # @return [void]
        def log_sender_change_event(event:, domain:, org:, actor:, provider: nil, changes: nil, details: nil, timestamp: Time.now.to_i)
          log_config_change_event(
            tag: 'DOMAIN_SENDER_CHANGE',
            event: event,
            domain: domain,
            org: org,
            actor: actor,
            extra: { provider: provider },
            changes: changes,
            details: details,
            timestamp: timestamp,
          )
        end

        # Compute changes between old config state and new parameters.
        #
        # @param old_config [Onetime::CustomDomain::MailerConfig] Existing configuration
        # @param new_params [Hash] New parameter values
        # @return [Hash] Changes hash with field names as keys
        def compute_sender_changes(old_config, new_params)
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
