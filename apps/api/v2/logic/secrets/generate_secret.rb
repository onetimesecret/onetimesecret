# apps/api/v2/logic/secrets/generate_secret.rb

require_relative 'base_secret_action'

module V2::Logic
  module Secrets

    using Familia::Refinements::TimeLiterals

    class GenerateSecret < BaseSecretAction
      def process_secret
        @kind = :generate

        # Get password generation configuration
        password_config = OT.conf.dig('site', 'secret_options', 'password_generation') || {}

        # Convert config keys to strings and merge with payload
        #
        # This is compatible with both v0.22 (mostly symbols) and v1.0
        # configuration (all strings).
        config_with_string_keys = password_config.transform_keys(&:to_s)
        payload_with_string_keys = payload.transform_keys(&:to_s)
        merged_options = config_with_string_keys.merge(payload_with_string_keys)

        # Extract parameters from merged options
        length = merged_options['length']&.to_i || merged_options['default_length'] || 12

        # Build character set options from merged configuration
        char_sets = merged_options['character_sets'] || {}

        secret_logger.debug "Generating secret",
          user_id: cust&.custid,
          length: length,
          char_sets: char_sets.keys,
          action: 'generate'
        # Use the configurable password generation method
        @secret_value = Onetime::Utils.strand(length, char_sets)
      end
    end
  end
end
