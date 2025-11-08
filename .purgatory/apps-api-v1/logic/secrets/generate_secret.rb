# .purgatory/apps-api-v1/logic/secrets/generate_secret.rb
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
        length = payload[:length]&.to_i || password_config['default_length'] || 12

        # Build character set options from payload or configuration
        char_sets = payload[:character_sets] || password_config['character_sets'] || {}

        # Use the configurable password generation method
        @secret_value = Onetime::Utils.strand(length, char_sets)
      end

    end
  end
end
