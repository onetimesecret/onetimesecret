# apps/api/organizations/logic/sso_config/audit_logger.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module SsoConfig
    # Audit logging for SSO configuration changes.
    #
    # Provides structured logging for security-sensitive SSO operations.
    # All events include actor, organization, timestamp, and IP address.
    #
    # SECURITY: Sensitive fields (client_id, client_secret) are NEVER logged.
    # For credential changes, we log only that the field changed, not its value.
    #
    # Events:
    #   - sso_config_created: New SSO configuration created
    #   - sso_config_replaced: Existing SSO configuration fully replaced (PUT)
    #   - sso_config_updated: SSO configuration partially updated (PATCH)
    #   - sso_config_deleted: SSO configuration removed
    #   - sso_config_enabled: SSO enabled for organization
    #   - sso_config_disabled: SSO disabled for organization
    #
    module AuditLogger
      # Fields that contain sensitive data and must never be logged
      SENSITIVE_FIELDS = %w[client_id client_secret].freeze

      # Fields safe to log with their actual values
      SAFE_FIELDS = %w[provider_type display_name enabled tenant_id issuer allowed_domains].freeze

      # Log an SSO audit event with structured data.
      #
      # @param event [String, Symbol] Event type (e.g., :sso_config_created)
      # @param org [Onetime::Organization] Organization being modified
      # @param actor [Onetime::Customer] User performing the action
      # @param provider_type [String] SSO provider type
      # @param changes [Hash, nil] Field changes for update events
      # @param details [Hash, nil] Additional event-specific details
      # @return [void]
      def log_sso_audit_event(event:, org:, actor:, provider_type:, changes: nil, details: nil)
        payload = build_audit_payload(
          event: event,
          org: org,
          actor: actor,
          provider_type: provider_type,
          changes: changes,
          details: details,
        )

        OT.info "[SSO_AUDIT] #{event}", payload.to_json
      end

      # Compute changes between old config state and new parameters.
      #
      # Compares fields and returns a hash indicating what changed.
      # Sensitive fields only indicate whether they changed, not their values.
      #
      # @param old_config [Onetime::OrgSsoConfig] Existing configuration
      # @param new_params [Hash] New parameter values
      # @return [Hash] Changes hash with field names as keys
      def compute_sso_changes(old_config, new_params)
        changes = {}

        # Check safe fields - log old and new values
        SAFE_FIELDS.each do |field|
          old_value = extract_old_value(old_config, field)
          new_value = extract_new_value(new_params, field)

          next if values_equal?(old_value, new_value)

          changes[field] = {
            from: old_value,
            to: new_value,
          }
        end

        # Check sensitive fields - only log that they changed, not their values.
        # We intentionally don't compare old vs new values for sensitive fields
        # since that would require decrypting them. Instead, we log a change
        # whenever a new value is provided in the params.
        SENSITIVE_FIELDS.each do |field|
          if sensitive_field_provided?(new_params, field)
            changes[field] = { changed: true }
          end
        end

        changes
      end

      private

      # Build the complete audit payload.
      #
      # @return [Hash] Structured audit data
      def build_audit_payload(event:, org:, actor:, provider_type:, changes:, details:)
        payload = {
          event: event.to_s,
          org_id: org.objid,
          org_extid: org.extid,
          actor_id: actor.custid,
          actor_email: actor.email,
          provider_type: provider_type,
          timestamp: Time.now.to_i,
          ip_address: extract_ip_address,
        }

        payload[:changes] = changes if changes && !changes.empty?
        payload[:details] = details if details && !details.empty?

        payload
      end

      # Extract IP address from strategy_result metadata.
      #
      # The IP is captured by AuthStrategies.build_metadata from env['REMOTE_ADDR'].
      #
      # @return [String, nil] Client IP address
      def extract_ip_address
        return nil unless respond_to?(:strategy_result)
        return nil unless strategy_result.respond_to?(:metadata)

        strategy_result.metadata[:ip]
      end

      # Extract old value from config for a field.
      #
      # @param config [Onetime::OrgSsoConfig] Config object
      # @param field [String] Field name
      # @return [Object] Field value
      def extract_old_value(config, field)
        case field
        when 'enabled'
          config.enabled?
        when 'allowed_domains'
          config.allowed_domains
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
        # Check both string and symbol keys
        value = params[field] || params[field.to_sym]

        case field
        when 'enabled'
          # Normalize to boolean
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
        # Normalize empty strings and nil
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

      # Check if a sensitive field has a value in the old config.
      #
      # @param config [Onetime::OrgSsoConfig]
      # @param field [String]
      # @return [Boolean]
      def sensitive_field_present?(config, field)
        return false unless config.respond_to?(field)

        concealed = config.send(field)
        return false if concealed.nil?

        # Check if the concealed value has content
        begin
          value = concealed.reveal { it }
          !value.to_s.empty?
        rescue StandardError
          false
        end
      end

      # Check if a sensitive field was provided in params (non-empty).
      #
      # @param params [Hash]
      # @param field [String]
      # @return [Boolean]
      def sensitive_field_provided?(params, field)
        value = params[field] || params[field.to_sym]
        !value.to_s.strip.empty?
      end
    end
  end
end
