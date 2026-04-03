# apps/api/domains/logic/incoming_config/serializers.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module IncomingConfig
      # Serialization helpers for incoming config responses.
      module Serializers
        # Serialize incoming config for API response.
        #
        # Returns public recipients (hashed emails) for security.
        #
        # @param config [Onetime::CustomDomain::IncomingConfig] The config to serialize
        # @return [Hash] Serialized config
        def serialize_incoming_config(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            recipients: config.public_recipients,
            max_recipients: Onetime::CustomDomain::IncomingConfig::MAX_RECIPIENTS,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end

        # Serialize incoming config with raw emails (admin view).
        #
        # Only used internally or for owner operations.
        #
        # @param config [Onetime::CustomDomain::IncomingConfig] The config to serialize
        # @return [Hash] Serialized config with raw emails
        def serialize_incoming_config_admin(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            recipients: config.recipients,
            max_recipients: Onetime::CustomDomain::IncomingConfig::MAX_RECIPIENTS,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end
      end
    end
  end
end
