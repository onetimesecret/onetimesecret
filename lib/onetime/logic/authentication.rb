
require_relative 'base'

module Onetime::Logic
  module Authentication

    class AuthenticateSession < OT::Logic::Base
      attr_reader :custid, :stay, :greenlighted
      attr_reader :session_ttl, :potential_custid

      # cust is only populated if the passphrase matches
      def process_params
        @potential_custid = params[:u].to_s.downcase.strip
        @passwd = self.class.normalize_password(params[:p])
        #@stay = params[:stay].to_s == "true"
        @stay = true # Keep sessions alive by default
        @session_ttl = (stay ? 30.days : 20.minutes).to_i

        if (potential = OT::Customer.load(@potential_custid))
          @cust = potential if potential.passphrase?(@passwd)
          @custid = @cust.custid if @cust
        end
      end

      def raise_concerns
        limit_action :authenticate_session
        if @cust.nil?
          @cust ||= OT::Customer.anonymous
          raise_form_error "Try again"
        end
      end

      def process

        if success?
          @greenlighted = true

          OT.info "[login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (replacing sessid)"

          # Create a completely new session, new id, new everything (incl
          # cookie which the controllor will implicitly do above when it
          # resends the cookie with the new session id).
          sess.replace!

          OT.info "[login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (new sessid)"

          sess.custid = cust.custid
          sess.authenticated = 'true'
          sess.ttl = session_ttl if @stay
          sess.save
          cust.save

          if OT.conf[:colonels].member?(cust.custid)
            cust.role = :colonel
          else
            cust.role = :customer unless cust.role?(:customer)
          end
        else
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

    class ResetPasswordRequest < OT::Logic::Base
      attr_reader :custid
      attr_accessor :token
      def process_params
        @custid = params[:u].to_s.downcase
      end

      def raise_concerns
        limit_action :forgot_password_request # limit requests

        raise_form_error "Not a valid email address" unless valid_email?(@custid)
        raise_form_error "No account found" unless OT::Customer.exists?(@custid)
      end

      def process
        cust = OT::Customer.load @custid
        secret = OT::Secret.create @custid, [@custid]
        secret.ttl = 24.hours
        secret.verification = "true"
        secret.save

        view = OT::App::Mail::PasswordRequest.new cust, locale, secret
        view.emailer.from = OT.conf[:emailer][:from]
        view.emailer.fromname = OT.conf[:emailer][:fromname]

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

    class ResetPassword < OT::Logic::Base
      attr_reader :secret, :is_confirmed
      def process_params
        @secret = OT::Secret.load params[:key].to_s
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
        @is_confirmed = Rack::Utils.secure_compare(@newp, @newp2)
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil?
        raise OT::MissingSecret if secret.custid.to_s == 'anon'

        limit_action :forgot_password_reset # limit reset attempts

        raise_form_error "New passwords do not match" unless is_confirmed
        raise_form_error "New password is too short" unless @newp.size >= 6
      end

      def process
        if is_confirmed
          # Load the customer information from the premade secret
          cust = secret.load_customer

          # Update the customer's passphrase
          cust.update_passphrase @newp

          # Set a success message in the session
          sess.set_success_message "Password changed"

          # Destroy the secret on successful attempt only. Otherwise
          # the user will need to make a new request if the passwords
          # don't match. We use rate limiting to discourage abuse.
          secret.destroy!

          # Log the success message
          OT.info "Password successfully changed for customer #{cust.custid}"

        else
          # Log the failure message
          OT.info "Password change failed: password confirmation not received"
        end

      end

      def success_data
        { custid: @cust.custid }
      end
    end


    class DestroySession < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        limit_action :destroy_session
        OT.info "[destroy-session] #{@custid} #{@sess.ipaddress}"
      end
      def process
        sess.destroy!
      end
    end

  end
end
