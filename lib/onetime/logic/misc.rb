
require_relative 'base'

module Onetime::Logic
  module Misc

    class ReceiveFeedback < OT::Logic::Base
      attr_reader :msg
      def process_params
        @msg = params[:msg].to_s.slice(0, 999)
      end

      def raise_concerns
        limit_action :send_feedback
        raise_form_error "You need an account to do that" if cust.anonymous?
        if @msg.empty? || @msg =~ /#{Regexp.escape("question or comment")}/
          raise_form_error "You can be more original than that!"
        end
      end

      def process
        @msg = "#{msg} [%s]" % [cust.anonymous? ? sess.ipaddress : cust.custid]
        OT.ld [:receive_feedback, msg].inspect
        OT::Feedback.add @msg
        sess.set_info_message "Message received. Send as much as you like!"
      end
    end

  end
end
