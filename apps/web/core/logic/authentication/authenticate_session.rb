# apps/web/core/logic/authentication/authenticate_session.rb

module Core::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class AuthenticateSession < V2::Logic::Base
      include Onetime::Logging
      attr_reader :objid, :stay, :greenlighted, :session_ttl, :potential_email_address

      # cust is only populated if the passphrase matches
      def process_params
        # NOTE: The parameter names should match what rodauth uses.
        @potential_email_address = params[:login].to_s.downcase.strip
        @passwd                  = self.class.normalize_password(params[:password])
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
        raise_form_error 'Invalid email or password', field: 'email', error_type: 'invalid'
      end

      def process
        unless success?
          auth_logger.warn "Login failed", {
            email: cust.obscure_email,
            role: cust.role,
            session_id: sess&.id,
            ip: @strategy_result.metadata[:ip],
            reason: :invalid_credentials
          }

          raise_form_error 'Invalid email or password', field: 'email', error_type: 'invalid'
        end

        if cust.pending?
          auth_logger.info "Login pending customer verification", {
            customer_id: cust.objid,
            email: cust.obscure_email,
            role: cust.role,
            session_id: sess&.id,
            status: :pending
          }

          auth_logger.info "Resending verification email", {
            customer_id: cust.objid,
            email: cust.obscure_email
          }

          send_verification_email nil

          msg = "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.objid}."
          set_info_message(msg)
          return success_data
        end

        @greenlighted = true

        # Set session authentication data
        sess['external_id'] = cust.extid
        sess['authenticated'] = true
        sess['authenticated_at'] = Familia.now.to_i
        cust.save

        colonels = OT.conf.dig('site', 'authentication', 'colonels') || []
        cust.role = if colonels.member?(cust.email)
          :colonel
        else
          :customer
        end

        auth_logger.info "Login successful", {
          user_id: cust.objid,
          email: cust.obscure_email,
          role: cust.role,
          session_id: sess.id,
          ip: @strategy_result.metadata[:ip],
          stay: stay,
          session_ttl: session_ttl
        }

        success_data
      end

      def success_data
        { objid: cust.objid, role: cust.role}
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
