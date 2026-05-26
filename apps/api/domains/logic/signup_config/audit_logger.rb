# apps/api/domains/logic/signup_config/audit_logger.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module SignupConfig
      # Audit logging for Domain Signup configuration changes.
      #
      # Provides structured logging for security-sensitive signup validation
      # operations. All events include actor, domain, organization, timestamp,
      # and IP address.
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
      module AuditLogger
        # Fields safe to log with their actual values
        SAFE_FIELDS = %w[validation_strategy enabled allowed_signup_domains].freeze

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
        def log_signup_audit_event(event:, domain:, org:, actor:, validation_strategy:, changes: nil, details: nil)
          payload = build_audit_payload(
            event: event,
            domain: domain,
            org: org,
            actor: actor,
            validation_strategy: validation_strategy,
            changes: changes,
            details: details,
          )

          OT.info "[DOMAIN_SIGNUP_AUDIT] #{event}", payload.to_json
        end

        # Compute changes between old config state and new parameters.
        #
        # Compares fields and returns a hash indicating what changed.
        #
        # @param old_config [Onetime::CustomDomain::SignupConfig] Existing configuration
        # @param new_params [Hash] New parameter values
        # @return [Hash] Changes hash with field names as keys
        def compute_signup_changes(old_config, new_params)
          changes = {}

          SAFE_FIELDS.each do |field|
            next unless field_provided?(new_params, field)

            old_value = extract_old_value(old_config, field)
            new_value = extract_new_value(new_params, field)

            next if values_equal?(old_value, new_value)

            changes[field] = {
              from: old_value,
              to: new_value,
            }
          end

          changes
        end

        private

        # Build the complete audit payload.
        #
        # @return [Hash] Structured audit data
        def build_audit_payload(event:, domain:, org:, actor:, validation_strategy:, changes:, details:)
          payload = {
            event: event.to_s,
            domain_id: domain.identifier,
            domain_display: domain.display_domain,
            org_id: org.objid,
            org_extid: org.extid,
            actor_id: actor.custid,
            actor_email: actor.email,
            validation_strategy: validation_strategy,
            timestamp: Time.now.to_i,
            ip_address: extract_ip_address,
          }

          payload[:changes] = changes if changes && !changes.empty?
          payload[:details] = details if details && !details.empty?

          payload
        end

        # Extract IP address from strategy_result metadata.
        #
        # @return [String, nil] Client IP address
        def extract_ip_address
          return nil unless respond_to?(:strategy_result)
          return nil unless strategy_result.respond_to?(:metadata)

          strategy_result.metadata[:ip]
        end

        # Extract old value from config for a field.
        #
        # @param config [Onetime::CustomDomain::SignupConfig] Config object
        # @param field [String] Field name
        # @return [Object] Field value
        def extract_old_value(config, field)
          case field
          when 'enabled'
            config.enabled?
          when 'allowed_signup_domains'
            config.allowed_signup_domains
          else
            config.send(field) if config.respond_to?(field)
          end
        end

        # Extract new value from params for a field.
        #
        # @param params [Hash] Parameter hash
        # @param field [String] Field name
        # @return [Object] Field value
        def extract_new_value(params, field)
          value = params[field] || params[field.to_sym]

          case field
          when 'enabled'
            case value
            when true, 'true', '1', 1
              true
            else
              false
            end
          else
            value
          end
        end

        # Check if values are equal, handling nil and type coercion.
        #
        # @param old_val [Object]
        # @param new_val [Object]
        # @return [Boolean]
        def values_equal?(old_val, new_val)
          old_normalized = normalize_value(old_val)
          new_normalized = normalize_value(new_val)

          old_normalized == new_normalized
        end

        # Normalize a value for comparison.
        #
        # @param val [Object]
        # @return [Object]
        def normalize_value(val)
          case val
          when nil, ''
            nil
          when Array
            val.map { it.to_s.strip.downcase }.reject(&:empty?).sort
          else
            val
          end
        end

        # Check if a field key exists in params.
        #
        # @param params [Hash]
        # @param field [String]
        # @return [Boolean]
        def field_provided?(params, field)
          params.key?(field) || params.key?(field.to_sym)
        end
      end
    end
  end
end
