# apps/api/domains/logic/sso_config/serializers.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module SsoConfig
      # Shared serialization methods for Domain SSO config API responses.
      #
      # Provides consistent serialization across GET and PUT endpoints,
      # including proper field masking for sensitive credentials.
      #
      module Serializers
        # Serialize SSO config for API response with masked secrets.
        #
        # Field naming matches TypeScript schema contract:
        # - client_secret_masked (not client_secret)
        # - created_at/updated_at as Unix timestamps
        #
        # @param config [Onetime::CustomDomain::SsoConfig] SSO config to serialize
        # @return [Hash] Serialized config matching TypeScript schema
        def serialize_sso_config(config)
          {
            domain_id: config.domain_id,
            provider_type: config.provider_type,
            display_name: config.display_name,
            enabled: config.enabled?,
            client_id: reveal_or_nil(config.client_id),
            client_secret_masked: mask_secret(config.client_secret),
            tenant_id: config.tenant_id,
            issuer: config.issuer,
            allowed_domains: config.allowed_domains,
            requires_domain_filter: config.requires_domain_filter?,
            idp_controls_access: config.idp_controls_access?,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end

        # Reveal encrypted field value or return nil.
        #
        # Logs warnings for decryption failures to aid debugging.
        #
        # @param concealed [Familia::ConcealedString, nil] Encrypted field
        # @return [String, nil] Plaintext value or nil
        def reveal_or_nil(concealed)
          return nil if concealed.nil?

          concealed.reveal { it }
        rescue StandardError => ex
          OT.lw "[SsoConfig::Serializers] Failed to reveal encrypted field: #{ex.class.name}"
          nil
        end

        # Mask a secret value, showing only last 4 characters.
        #
        # Logs warnings for decryption failures to aid debugging.
        #
        # @param concealed [Familia::ConcealedString, nil] Encrypted secret
        # @return [String, nil] Masked secret (e.g., "••••••••abcd") or nil
        def mask_secret(concealed)
          return nil if concealed.nil?

          plaintext = concealed.reveal { it }
          return nil if plaintext.nil? || plaintext.empty?

          if plaintext.length <= 4
            '••••••••'
          else
            '••••••••' + plaintext[-4..]
          end
        rescue StandardError => ex
          OT.lw "[SsoConfig::Serializers] Failed to mask secret: #{ex.class.name}"
          nil
        end
      end
    end
  end
end
