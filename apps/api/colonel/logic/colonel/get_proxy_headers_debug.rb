# apps/api/colonel/logic/colonel/get_proxy_headers_debug.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Returns the selected request metadata captured by Colonel's session
      # strategy for the diagnostic route. The route is already protected by
      # Colonel role auth and AdminNetworkIsolation's host/CIDR gates.
      class GetProxyHeadersDebug < ColonelAPI::Logic::Base
        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          success_data
        end

        def success_data
          strategy_result.metadata.fetch(:proxy_header_debug, {})
        end
      end
    end
  end
end
