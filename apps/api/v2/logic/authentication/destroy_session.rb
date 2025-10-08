# apps/api/v2/logic/authentication/destroy_session.rb

module V2::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class DestroySession < V2::Logic::Base
      def process_params; end

      def raise_concerns
        OT.info "[destroy-session] #{@custid} #{@sess.inspect}"
      end

      def process
        # Rack session doesn't have destroy! - use clear to remove all data
        sess.clear
      end
    end
  end
end
