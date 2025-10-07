# apps/api/v2/logic/authentication/reset_password_request.rb

require_relative '../base'

module V2::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class ResetPasswordRequest < V2::Logic::Base
      attr_reader :objid
      attr_accessor :token

      def process_params
        @objid = params[:u].to_s.downcase
      end

      def raise_concerns
        raise_form_error 'Not a valid email address' unless valid_email?(@custid)
        raise_form_error 'No account found' unless Onetime::Customer.exists?(@custid)
      end

      def process
        cust = Onetime::Customer.load @custid

        if cust.pending?
          OT.li "[ResetPasswordRequest] Resending verification email to #{cust.objid}"
          send_verification_email
          msg = "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.objid}."
          return set_info_message(msg)
        end

        secret                    = Onetime::Secret.create @objid, [@objid]
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.save

        cust.reset_secret = secret.key  # as a standalone dbkey, writes immediately

        view = OT::Mail::PasswordRequest.new cust, locale, secret

        OT.ld "Calling deliver_email with token=(#{token})"

        begin
          view.deliver_email token
        rescue StandardError => ex
          errmsg = "Couldn't send the notification email. Let know below."
          OT.le "Error sending password reset email: #{ex.message}"
          set_error_message(errmsg)
        else
          OT.info "Password reset email sent to #{@objid} for sess=#{short_session_id}"
          set_info_message "We sent instructions to #{cust.objid}"
        end
      end

      def success_data
        { objid: @cust.objid }
      end
    end
  end
end
