# apps/api/v1/logic/secrets/generate_secret.rb
#
# frozen_string_literal: true

require_relative 'base_secret_action'

module V1::Logic
  module Secrets
    class GenerateSecret < BaseSecretAction

      def process_secret
        @kind = :generate

        # Get password generation configuration
        password_config = OT.conf.dig('site', 'secret_options', 'password_generation') || {}

        # Extract parameters from payload with fallbacks to configuration
        length = payload['length']&.to_i || password_config['default_length'] || 12

        # Reject oversized lengths BEFORE strand allocates (DoS guard). Read the
        # ceiling from CONFIG, not the payload, so a caller cannot lift the guard.
        # Mirrors the v2 generate cap and the frontend Zod max.
        max_length = (password_config['maximum_length'] || 128).to_i
        if length > max_length
          raise_form_error "Generated password length must be no more than #{max_length} characters", field: :length
        end

        # Build character set options from payload or configuration
        char_sets = payload['character_sets'] || password_config['character_sets'] || {}

        # Use the configurable password generation method
        @secret_value = Onetime::Utils.strand(length, char_sets)
      end

    end
  end
end
