# apps/api/v2/logic/incoming/get_config.rb

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
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        limit_action :get_page
      end

      def process
        incoming_config = OT.conf.dig(:features, :incoming) || {}

        # Filter out sensitive fields like default_passphrase
        @config_data = {
          enabled: incoming_config[:enabled] || false,
          title_max_length: incoming_config[:title_max_length] || 50,
          default_ttl: incoming_config[:default_ttl] || 604800,
          recipients: (incoming_config[:recipients] || []).map do |r|
            {
              email: r[:email],
              name: r[:name] || r[:email]
            }
          end
        }

        @greenlighted = true
      end

      def success_data
        {
          config: config_data
        }
      end
    end
  end
end
