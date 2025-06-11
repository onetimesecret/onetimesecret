# apps/api/v2/logic/authentication/reset_password_request.rb

require_relative '../base'

module V2::Logic
  module Authentication
    class ResetPasswordRequest < V2::Logic::Base
      attr_reader :custid
      attr_accessor :token
      def process_params
        @custid = params[:u].to_s.downcase
      end

      def raise_concerns
        limit_action :forgot_password_request # limit requests

        raise_form_error 'Not a valid email address' unless valid_email?(@custid)
        raise_form_error 'No account found' unless V2::Customer.exists?(@custid)
      end

      def process
        cust = V2::Customer.load @custid

        if cust.pending?
          OT.li "[ResetPasswordRequest] Resending verification email to #{cust.custid}"
          self.send_verification_email
          msg = "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.custid}."
          return sess.set_info_message msg
        end

        secret = V2::Secret.create @custid, [@custid]
        secret.ttl = 24.hours
        secret.verification = 'true'
        secret.save

        cust.reset_secret = secret.key  # as a standalone rediskey, writes immediately

        view = OT::Mail::PasswordRequest.new cust, locale, secret

        OT.ld "Calling deliver_email with token=(#{self.token})"

        begin
          view.deliver_email self.token

        rescue StandardError => ex
          errmsg = "Couldn't send the notification email. Let know below."
          OT.le "Error sending password reset email: #{ex.message}"
          sess.set_error_message errmsg
        else
          OT.info "Password reset email sent to #{@custid} for sess=#{sess.short_identifier}"
          sess.set_success_message "We sent instructions to #{cust.custid}"
        end

      end

      def success_data
        { custid: @cust.custid }
      end
    end
  end
end
