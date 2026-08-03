# apps/api/domains/logic/signin_config/change_logger.rb
#
# frozen_string_literal: true

require_relative '../config_change_logger'

module DomainsAPI
  module Logic
    module SigninConfig
      # Audit logging for Domain Signin configuration changes.
      #
      # Shared machinery lives in DomainsAPI::Logic::ConfigChangeLogger.
      # SigninConfig has no sensitive fields, so all values are safe to log.
      #
      # Events:
      #   - domain_signin_config_created: New signin configuration created
      #   - domain_signin_config_replaced: Existing configuration fully replaced (PUT)
      #   - domain_signin_config_deleted: Configuration removed
      #   - domain_signin_config_enabled: Signin config enabled for domain
      #   - domain_signin_config_disabled: Signin config disabled for domain
      #
      module ChangeLogger
        include DomainsAPI::Logic::ConfigChangeLogger

        # Log a Domain Signin audit event with structured data.
        #
        # @param event [String, Symbol] Event type
        # @param domain [Onetime::CustomDomain] Domain being modified
        # @param org [Onetime::Organization] Organization that owns the domain
        # @param actor [Onetime::Customer] User performing the action
        # @param details [Hash, nil] Additional event-specific details
        # @return [void]
        def log_signin_change_event(event:, domain:, org:, actor:, details: nil)
          log_config_change_event(
            tag: 'DOMAIN_SIGNIN_CHANGE',
            event: event,
            domain: domain,
            org: org,
            actor: actor,
            details: details,
          )
        end
      end
    end
  end
end
