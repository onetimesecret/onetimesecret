# apps/api/domains/logic/config_change_logger.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    # Shared machinery for the per-config ChangeLogger modules
    # (SsoConfig, SenderConfig, SignupConfig, SigninConfig).
    #
    # Each per-config module keeps its own public entry points
    # (log_*_change_event / compute_*_changes) plus its field lists and log
    # tag; this module provides the payload construction, change
    # computation, and value normalization they all share.
    #
    # All events include actor, domain, organization, timestamp, and IP
    # address.
    #
    # SECURITY: Sensitive fields are NEVER logged with their values. For
    # credential changes we log only that the field changed.
    #
    module ConfigChangeLogger
      private

      # Build and emit a structured audit event.
      #
      # @param tag [String] Log tag, e.g. 'DOMAIN_SSO_CHANGE'
      # @param event [String, Symbol] Event type
      # @param domain [Onetime::CustomDomain] Domain being modified
      # @param org [Onetime::Organization] Organization that owns the domain
      # @param actor [Onetime::Customer] User performing the action
      # @param extra [Hash] Config-specific payload keys (e.g. provider_type),
      #   emitted between the actor and timestamp keys
      # @param changes [Hash, nil] Field changes for update events
      # @param details [Hash, nil] Additional event-specific details
      # @param timestamp [Integer] Unix timestamp; pass explicitly when
      #   multiple audit events in one request must share the same value
      # @return [void]
      def log_config_change_event(tag:, event:, domain:, org:, actor:, extra: {}, changes: nil, details: nil, timestamp: Time.now.to_i)
        payload              = {
          event: event.to_s,
          domain_id: domain.identifier,
          domain_display: domain.display_domain,
          org_id: org.objid,
          org_extid: org.extid,
          actor_id: actor.custid,
          actor_email: actor.email,
        }
        payload.merge!(extra)
        payload[:timestamp]  = timestamp
        payload[:ip_address] = extract_ip_address

        payload[:changes] = changes if changes && !changes.empty?
        payload[:details] = details if details && !details.empty?

        OT.info "[#{tag}] #{event}", payload.to_json
      end

      # Compute changes between old config state and new parameters.
      #
      # Safe fields log old and new values; sensitive fields only indicate
      # that they changed. Boolean fields read the old value via the
      # config's predicate method and coerce the new value to true/false.
      #
      # @param old_config [Object] Existing configuration
      # @param new_params [Hash] New parameter values
      # @param safe_fields [Array<String>] Fields logged with their values
      # @param sensitive_fields [Array<String>] Fields logged as changed-only
      # @param boolean_fields [Array<String>] Subset of safe_fields
      # @return [Hash] Changes hash with field names as keys
      def compute_config_changes(old_config, new_params, safe_fields:, sensitive_fields: [], boolean_fields: [])
        changes = {}

        safe_fields.each do |field|
          next unless field_provided?(new_params, field)

          old_value = extract_old_value(old_config, field, boolean_fields)
          new_value = extract_new_value(new_params, field, boolean_fields)

          next if values_equal?(old_value, new_value)

          changes[field] = { from: old_value, to: new_value }
        end

        sensitive_fields.each do |field|
          changes[field] = { changed: true } if sensitive_field_provided?(new_params, field)
        end

        changes
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
      # @param config [Object] Config object
      # @param field [String] Field name
      # @param boolean_fields [Array<String>]
      # @return [Object] Field value
      def extract_old_value(config, field, boolean_fields)
        if boolean_fields.include?(field)
          predicate = :"#{field}?"
          config.public_send(predicate) if config.respond_to?(predicate)
        elsif config.respond_to?(field)
          config.send(field)
        end
      end

      # Extract new value from params for a field.
      #
      # @param params [Hash] Parameter hash
      # @param field [String] Field name
      # @param boolean_fields [Array<String>]
      # @return [Object] Field value
      def extract_new_value(params, field, boolean_fields)
        value = params[field] || params[field.to_sym]

        return value unless boolean_fields.include?(field)

        case value
        when true, 'true', '1', 1
          true
        else
          false
        end
      end

      # Check if values are equal, handling nil and type coercion.
      #
      # @param old_val [Object]
      # @param new_val [Object]
      # @return [Boolean]
      def values_equal?(old_val, new_val)
        normalize_value(old_val) == normalize_value(new_val)
      end

      # Normalize a value for comparison: nil and '' collapse to the same
      # nil bucket; arrays compare order- and case-insensitively.
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
