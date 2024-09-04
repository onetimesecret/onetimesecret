
require_relative '../../altcha'
require_relative 'base'

module Onetime::Logic
  module Misc

    class ReceiveFeedback < OT::Logic::Base
      attr_reader :msg, :altcha_payload, :verified, :verification_data

      def process_params
        @msg = params[:msg].to_s.slice(0, 999)
        @altcha_payload = params[:altcha].to_s.slice(0, 999)
      end

      def raise_concerns
        limit_action :send_feedback

        raise_form_error "You can be more original than that!" if @msg.empty?

        if cust.anonymous?
          raise_form_error "You need to be carbon-based to do that" if altcha_payload.empty?
          raise_form_error "Invalid Altcha payload" unless verify_altcha_payload
        end
      end

      def verify_altcha_payload
        @verified = Altcha.verify_solution(altcha_payload, secret_key)
      end

      def filter_spam_altcha_payload
        @verified, @verification_data = Altcha.verify_server_signature(altcha_payload, secret_key)

        fields_verified = Altcha.verify_fields_hash(
          params,
          verification_data.fields,
          verification_data.fields_hash,
          'SHA-256'
        )

        verified && fields_verified
      end

      def process
        @msg = "#{msg} [%s]" % [cust.anonymous? ? sess.ipaddress : cust.custid]
        OT.ld [:receive_feedback, msg].inspect
        OT::Feedback.add @msg
        sess.set_info_message "Message received. Send as much as you like!"
      end

      def secret_key
        OT.conf.dig(:site, :authenticity, :secret_key) # ALTCHA_HMAC_KEY
      end
    end

  end
end
