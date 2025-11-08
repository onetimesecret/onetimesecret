# apps/api/v1/logic/authentication/authenticate_session.rb
#
# frozen_string_literal: true

require_relative '../base'

module V1::Logic
  module Authentication

    using Familia::Refinements::TimeLiterals

    class AuthenticateSession < V1::Logic::Base
      attr_reader :custid, :stay, :greenlighted
      attr_reader :session_ttl, :potential_custid

      # cust is only populated if the passphrase matches
      def process_params
        @potential_custid = params[:u].to_s.downcase.strip
        @passwd = self.class.normalize_password(params[:p])
        #@stay = params[:stay].to_s == "true"
        @stay = true # Keep sessions alive by default
        @session_ttl = (stay ? 30.days : 20.minutes).to_i

        if (potential = V1::Customer.load(@potential_custid))
          @cust = potential if potential.passphrase?(@passwd)
          @custid = @cust.custid if @cust
        end
      end

      def raise_concerns

        if @cust.nil?
          @cust ||= V1::Customer.anonymous
          raise_form_error "Try again"
        end
      end

      def process
        if success?
          if cust.pending?
            OT.info "[login-pending-customer] #{sess.short_identifier} #{cust.custid} #{cust.role} (pending)"
            OT.li "[ResetPasswordRequest] Resending verification email to #{cust.custid}"
            self.send_verification_email nil

            # NOTE: i18n keys as symbols
            msg = "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.custid}."
            return sess.set_info_message msg
          end

          @greenlighted = true

          OT.info "[login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (replacing sessid)"

          # Create a completely new session, new id, new everything (incl
          # cookie which the controllor will implicitly do above when it
          # resends the cookie with the new session id).
          sess.replace!

          OT.info "[login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (new sessid)"

          sess.custid = cust.custid
          sess.authenticated = 'true'
          sess.default_expiration = session_ttl if @stay
          sess.save
          cust.save

          colonels = OT.conf.dig("site", "authentication", "colonels") || []
          if colonels.member?(cust.custid)
            cust.role = :colonel
          else
            cust.role = :customer unless cust.role?(:customer)
          end

        else
          OT.ld "[login-failure] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (failed)"
          raise_form_error "Try again"
        end
      end

      def success?
        !cust&.anonymous? && (cust.passphrase?(@passwd) || @colonel&.passphrase?(@passwd))
      end

      private
      def form_fields
        {:custid => custid}
      end
    end
  end
end
