# apps/api/v2/logic/authentication/destroy_session.rb

module V2::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class DestroySession < V2::Logic::Base
      include Onetime::Logging

      def process_params; end

      def raise_concerns
        auth_logger.debug "Session destruction initiated",
          customer_id: @custid,
          session_id: sess&.id,
          ip: @strategy_result&.metadata&.dig(:ip)
      end

      def process
        # Rack session doesn't have destroy! - use clear to remove all data
        sess.clear

        auth_logger.info "Session destroyed",
          customer_id: @custid,
          session_id: sess&.id,
          ip: @strategy_result&.metadata&.dig(:ip)

        {}
      end
    end
  end
end
