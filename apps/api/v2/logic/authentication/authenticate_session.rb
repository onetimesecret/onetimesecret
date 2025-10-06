# apps/api/v2/logic/authentication/authenticate_session.rb

module V2::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class AuthenticateSession < V2::Logic::Base
      attr_reader :objid, :stay, :greenlighted, :session_ttl, :potential_email_address

      # cust is only populated if the passphrase matches
      def process_params
        @potential_email_address = params[:u].to_s.downcase.strip
        @passwd                  = self.class.normalize_password(params[:p])
        @stay                    = true # Keep sessions alive by default
        @session_ttl             = (stay ? 30.days : 20.minutes).to_i

        potential = Onetime::Customer.find_by_email(potential_email_address)

        return unless potential

        passwd_matches = potential.passphrase?(@passwd)
        @cust          = potential if passwd_matches
        @objid         = @cust.objid if @cust
      end

      def raise_concerns
        return unless @cust.nil?

        @cust ||= Onetime::Customer.anonymous
        raise_form_error 'Try again'
      end

      def process
        if success?
          if cust.pending?
            OT.info "[login-pending-customer] #{sess.short_identifier} #{cust.objid} #{cust.role} (pending)"
            OT.li "[ResetPasswordRequest] Resending verification email to #{cust.objid}"
            send_verification_email nil

            msg = "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.objid}."
            return sess.set_info_message msg
          end

          @greenlighted = true

          OT.info "[login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (replacing sessid)"

          # Create a completely new session, new id, new everything (incl
          # cookie which the controllor will implicitly do above when it
          # resends the cookie with the new session id).
          sess.replace!

          OT.info "[login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (new sessid)"

          sess.objid              = cust.objid
          sess.authenticated      = 'true'
          sess.default_expiration = session_ttl if @stay
          sess.save
          cust.save

          colonels = OT.conf.dig('site', 'authentication', 'colonels') || []
          if colonels.member?(cust.objid)
            cust.role = :colonel
          else
            cust.role = :customer unless cust.role?(:customer)
          end

        else
          OT.ld "[login-failure] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (failed)"
          raise_form_error 'Try again'
        end
      end

      def success?
        !cust&.anonymous? && (cust.passphrase?(@passwd) || @colonel&.passphrase?(@passwd))
      end

      private

      def form_fields
        { objid: objid }
      end
    end
  end
end
