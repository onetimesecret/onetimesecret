# apps/api/domains/logic/signin_config/audit_logger.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module SigninConfig
      # Audit logging for Domain Signin configuration changes.
      #
      # Provides structured logging for sign-in policy changes.
      # SigninConfig has no sensitive fields, so all values are safe to log.
      #
      # Events:
      #   - domain_signin_config_created: New signin configuration created
      #   - domain_signin_config_replaced: Existing configuration fully replaced (PUT)
      #   - domain_signin_config_deleted: Configuration removed
      #   - domain_signin_config_enabled: Signin config enabled for domain
      #   - domain_signin_config_disabled: Signin config disabled for domain
      #
      module AuditLogger
        # Log a Domain Signin audit event with structured data.
        #
        # @param event [String, Symbol] Event type
        # @param domain [Onetime::CustomDomain] Domain being modified
        # @param org [Onetime::Organization] Organization that owns the domain
        # @param actor [Onetime::Customer] User performing the action
        # @param details [Hash, nil] Additional event-specific details
        # @return [void]
        def log_signin_audit_event(event:, domain:, org:, actor:, details: nil)
          payload = {
            event: event.to_s,
            domain_id: domain.identifier,
            domain_display: domain.display_domain,
            org_id: org.objid,
            org_extid: org.extid,
            actor_id: actor.custid,
            actor_email: actor.email,
            timestamp: Time.now.to_i,
            ip_address: extract_ip_address,
          }

          payload[:details] = details if details && !details.empty?

          OT.info "[DOMAIN_SIGNIN_AUDIT] #{event}", payload.to_json
        end

        private

        # Extract IP address from strategy_result metadata.
        #
        # @return [String, nil] Client IP address
        def extract_ip_address
          return nil unless respond_to?(:strategy_result)
          return nil unless strategy_result.respond_to?(:metadata)

          strategy_result.metadata[:ip]
        end
      end
    end
  end
end
