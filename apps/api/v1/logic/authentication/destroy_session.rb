# apps/api/v1/logic/authentication/destroy_session.rb

require_relative '../base'

module V1::Logic
  module Authentication
    class DestroySession < V1::Logic::Base
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
