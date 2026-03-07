# apps/api/v3/logic/incoming/get_config.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/incoming/recipient_resolver'

module V3
  module Logic
    module Incoming
      # Returns the incoming secrets configuration for the frontend.
      #
      # Domain-aware: canonical domains return global YAML recipients;
      # custom domains return per-domain Redis recipients.
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
      # @api Retrieve the incoming secrets feature configuration, including
      #   whether the feature is enabled, memo length limits, default TTL,
      #   and the list of available recipients identified by hash.
      class GetConfig < V3::Logic::Base
        SCHEMAS = { response: 'incomingConfig' }.freeze

        attr_reader :greenlighted, :config_data

        def process_params
          # No params needed for get_config
        end

        def raise_concerns
          # No concerns to raise. The feature may be disabled; the frontend
          # renders a "feature disabled" state when config.enabled is false.
          # Raising FormError here would show the error state instead.
        end

        def process
          resolver = Onetime::Incoming::RecipientResolver.new(
            domain_strategy: domain_strategy,
            display_domain: display_domain,
          )

          @config_data = resolver.config_data

          Onetime.secret_logger.debug "[IncomingConfig] Returning #{@config_data[:recipients].size} recipients (hashed) for #{domain_strategy || 'default'}"

          @greenlighted = true

          success_data
        end

        def success_data
          {
            config: config_data,
          }
        end
      end
    end
  end
end
