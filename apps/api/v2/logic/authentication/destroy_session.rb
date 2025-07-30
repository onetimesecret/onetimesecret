# apps/api/v2/logic/authentication/destroy_session.rb

module V2::Logic
  module Authentication
    class DestroySession < V2::Logic::Base
      def process_params
      end
      def raise_concerns

        OT.info "[destroy-session] #{@custid} #{@sess.ipaddress}"
      end
      def process
        sess.destroy!
      end
    end
  end
end
