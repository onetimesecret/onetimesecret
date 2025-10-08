# apps/api/v2/logic/authentication/destroy_session.rb

module V2::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class DestroySession < V2::Logic::Base
      def process_params; end

      def raise_concerns
        # Note: @sess here is the Rack session hash, not a Session model
        ip = @strategy_result&.metadata&.dig(:ip) || 'unknown'
        OT.info "[destroy-session] #{@cust&.objid} #{ip}"
      end

      def process
        # Clear the Rack session
        sess.clear
        sess['authenticated'] = false
        sess.delete('identity_id')
      end
    end
  end
end
