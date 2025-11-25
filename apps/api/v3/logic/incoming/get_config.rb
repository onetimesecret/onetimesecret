# apps/api/v3/logic/incoming/get_config.rb
#
# frozen_string_literal: true

require_relative '../base'

module V3
  module Logic
    module Incoming
      # Returns the incoming secrets configuration for the frontend.
      #
      # This includes:
      # - Whether the feature is enabled
      # - Maximum memo length
      # - Default TTL
      # - List of available recipients (hashed, not actual emails)
      #
      # @example Response
      #   {
      #     config: {
      #       enabled: true,
      #       memo_max_length: 50,
      #       default_ttl: 604800,
      #       recipients: [
      #         { hash: "abc123...", name: "Support Team" }
      #       ]
      #     }
      #   }
      #
      class GetConfig < V3::Logic::Base
        attr_reader :greenlighted, :config_data

        def process_params
          # No params needed for get_config
        end

        def raise_concerns
          # Check if feature is enabled
          incoming_config = OT.conf.dig('features', 'incoming') || {}
          unless incoming_config['enabled']
            raise_form_error 'Incoming secrets feature is not enabled'
          end
        end

        def process
          incoming_config = OT.conf.dig('features', 'incoming') || {}

          # Use hashed recipients to prevent email exposure
          @config_data = {
            enabled: incoming_config['enabled'] || false,
            memo_max_length: incoming_config['memo_max_length'] || 50,
            default_ttl: incoming_config['default_ttl'] || 604_800,
            recipients: OT.incoming_public_recipients # Returns hashed version
          }

          Onetime.secret_logger.debug "[IncomingConfig] Returning #{@config_data[:recipients].size} recipients (hashed)"

          @greenlighted = true

          success_data
        end

        def success_data
          {
            config: config_data
          }
        end
      end
    end
  end
end
