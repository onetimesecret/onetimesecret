# apps/api/domains/logic/sender_config/serializers.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module SenderConfig
      # Shared serialization methods for Domain Sender Config API responses.
      #
      # Provides consistent serialization across GET, PUT, and PATCH endpoints,
      # including proper field masking for sensitive credentials.
      #
      module Serializers
        # Serialize mailer config for API response with masked secrets.
        #
        # @param config [Onetime::CustomDomain::MailerConfig] Mailer config to serialize
        # @return [Hash] Serialized config for JSON response
        def serialize_sender_config(config)
          {
            domain_id: config.domain_id,
            provider: config.provider.to_s.empty? ? 'inherit' : config.provider,
            from_name: config.from_name,
            from_address: config.from_address,
            reply_to: config.reply_to,
            enabled: config.enabled?,
            validation_status: config.verification_status || 'pending',
            verified: config.verified?,
            sending_mode: config.sending_mode,
            dns_records: config.required_dns_records,
            provider_dns_data: config.provider_dns_data&.value,
            provider_domain_id: nil,
            api_key_masked: mask_secret(config.api_key),
            last_validated_at: config.verified_at.to_s.empty? ? nil : config.verified_at.to_i,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
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
          OT.lw "[SenderConfig::Serializers] Failed to mask secret: #{ex.class.name}"
          nil
        end
      end
    end
  end
end
