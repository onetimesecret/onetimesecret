# apps/api/v2/logic/incoming/get_config.rb
#
# frozen_string_literal: true

require_relative '../base'

module V2::Logic
  module Incoming
    class GetConfig < V2::Logic::Base
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

        limit_action :get_page
      end

      def process
        incoming_config = OT.conf.dig('features', 'incoming') || {}

        # Use hashed recipients to prevent email exposure
        @config_data = {
          enabled: incoming_config['enabled'] || false,
          memo_max_length: incoming_config['memo_max_length'] || 50,
          default_ttl: incoming_config['default_ttl'] || 604_800,
          recipients: OT.incoming_public_recipients,  # Returns hashed version
        }

        OT.ld "[IncomingConfig] Returning #{@config_data[:recipients].size} recipients (hashed)"

        @greenlighted = true
      end

      def success_data
        {
          config: config_data,
        }
      end
    end
  end
end
