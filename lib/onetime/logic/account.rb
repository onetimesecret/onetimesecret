
require_relative 'base'

module Onetime::Logic
  module Account

    class ViewAccount < OT::Logic::Base
      def process_params
      end

      def raise_concerns
        limit_action :show_account
      end

      def process
      end
    end

    class CreateAccount < OT::Logic::Base
      attr_reader :cust, :plan, :autoverify, :customer_role
      attr_reader :planid, :custid, :password, :password2, :skill
      attr_accessor :token
      def process_params
        @planid = params[:planid].to_s
        @custid = params[:u].to_s.downcase.strip

        @password = self.class.normalize_password(params[:p])
        @password2 = self.class.normalize_password(params[:p2])

        @autoverify = OT.conf&.dig(:site, :authentication, :autoverify).eql?(true) || false

        # This is a hidden field, so it should be empty. If it has a value, it's
        # a simple bot trying to submit the form or similar chicanery. We just
        # quietly redirect to the home page to mimic a successful response.
        @skill = params[:skill].to_s.strip.slice(0,60)
      end

      def raise_concerns
        limit_action :create_account
        raise OT::FormError, "You're already signed up" if sess.authenticated?
        raise_form_error "Username not available" if OT::Customer.exists?(custid)
        raise_form_error "Is that a valid email address?" unless valid_email?(custid)
        raise_form_error "Passwords do not match" unless password == password2
        raise_form_error "Password is too short" unless password.size >= 6
        raise_form_error "Unknown plan type" unless OT::Plan.plan?(planid)

        # Quietly redirect suspected bots to the home page.
        unless skill.empty?
          raise OT::Redirect.new('/?s=1') # the query string is arbitrary, for log filtering
        end
      end
      def process


        @plan = OT::Plan.plan(planid)
        @cust = OT::Customer.create custid

        cust.update_passphrase password
        sess.update_fields(custid: cust.custid)

        @customer_role = if OT.conf[:colonels].member?(cust.custid)
                           'colonel'
                         else
                           'customer'
                         end

        cust.update_fields(planid: @plan.planid, verified: @autoverify.to_s, role: @customer_role)

        OT.info "[new-customer] #{cust.custid} #{cust.role} #{sess.ipaddress} #{plan.planid} #{sess.short_identifier}"
        OT::Logic.stathat_count("New Customers (OTS)", 1)

        if autoverify
          sess.set_info_message "Account created"
        else
          self.send_verification_email
        end

      end

      private

      def send_verification_email
        _, secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier], token

        msg = "Thanks for verifying your account. We got you a secret fortune cookie!\n\n\"%s\"" % OT::Utils.random_fortune

        secret.encrypt_value msg
        secret.verification = true
        secret.custid = cust.custid
        secret.save

        view = OT::App::Mail::Welcome.new cust, locale, secret

        begin
          view.deliver_email self.token

        rescue StandardError => ex
          errmsg = "Couldn't send the verification email. Let us know below."
          OT.le "Error sending verification email: #{ex.message}"
          sess.set_info_message errmsg
        end
      end

      def form_fields
        { :planid => planid, :custid => custid }
      end
    end

    class ResetPasswordRequest < OT::Logic::Base
      attr_reader :custid
      attr_accessor :token
      def process_params
        @custid = params[:u].to_s.downcase
      end

      def raise_concerns
        limit_action :forgot_password_request
        raise_form_error "Not a valid email address" unless valid_email?(@custid)
        raise_form_error "No account found" unless OT::Customer.exists?(@custid)
      end

      def process
        cust = OT::Customer.load @custid
        secret = OT::Secret.create @custid, [@custid]
        secret.ttl = 24.hours
        secret.verification = true

        view = OT::App::Mail::PasswordRequest.new cust, locale, secret
        view.emailer.from = OT.conf[:emailer][:from]
        view.emailer.fromname = OT.conf[:emailer][:fromname]

        OT.ld "Calling deliver_email with token=(#{self.token})"

        begin
          view.deliver_email self.token

        rescue StandardError => ex
          errmsg = "Couldn't send the notification email. Let know below."
          OT.le "Error sending password reset email: #{ex.message}"
          sess.set_info_message errmsg
        else
          sess.set_info_message "We sent instructions to #{cust.custid}"
        end

      end

      def success_data
        { custid: @cust.custid }
      end
    end

    class ResetPassword < OT::Logic::Base
      attr_reader :secret
      def process_params
        @secret = OT::Secret.load params[:key].to_s
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil?
        raise OT::MissingSecret if secret.custid.to_s == 'anon'
        limit_action :forgot_password_reset
        raise_form_error "New passwords do not match" unless @newp == @newp2
        raise_form_error "New password is too short" unless @newp.size >= 6
        raise_form_error "New password cannot match current password" if @newp == @currentp
      end

      def process
        cust = secret.load_customer
        cust.update_passphrase @newp
        sess.set_info_message "Password changed"
        secret.destroy!
      end

      def success_data
        { custid: @cust.custid }
      end
    end

    class UpdateAccount < OT::Logic::Base
      attr_reader :modified, :greenlighted

      def process_params
        @currentp = self.class.normalize_password(params[:currentp])
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
        @passgen_token = self.class.normalize_password(params[:passgen_token], 60)
      end

      def raise_concerns
        @modified ||= []
        limit_action :update_account
        if ! @currentp.empty?
          raise_form_error "Current password is incorrect" unless cust.passphrase?(@currentp)
          raise_form_error "New password cannot be the same as current password" if @newp == @currentp
          raise_form_error "New password is too short" unless @newp.size >= 6
          raise_form_error "New passwords do not match" unless @newp == @newp2
        end
        if ! @passgen_token.empty?
          raise_form_error "Token is too short" if @passgen_token.size < 6
        end
      end

      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          @greenlighted = true
          OT.info "[update-account] Password updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          cust.update_passphrase @newp
          @modified << :password
        end
      end

      def modified? field_name
        modified.member? field_name
      end

      def success_data
        {}
      end
    end

    class DestroyAccount < OT::Logic::Base
      attr_reader :raised_concerns_was_called, :greenlighted

      def process_params
        return if params.nil?
        @confirmation = self.class.normalize_password(params[:confirmation])
      end

      def raise_concerns
        @raised_concerns_was_called = true

        # It's vitally important for the limiter to run prior to any
        # other concerns. This prevents a malicious user from
        # attempting to brute force the password.
        #
        limit_action :destroy_account

        if @confirmation&.empty?
          raise_form_error "Password confirmation is required."
        else
          OT.info "[destroy-account] Passphrase check attempt cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          unless cust.passphrase?(@confirmation)
            raise_form_error "Please check the password."
          end
        end
      end

      def process
        # This is very defensive programming. When it comes to
        # destroying things though, let's pull out all the stops.
        unless raised_concerns_was_called
          raise_form_error "We have concerns about that request."
        end

        if cust.passphrase?(@confirmation)
          # All criteria to destroy the account have been met.
          @greenlighted = true

          # Process the customer's request to destroy their account.
          if Onetime.debug
            OT.ld "[destroy-account] Simulated account destruction #{cust.custid} #{cust.role} #{sess.ipaddress}"

            # Since we intentionally don't call Customer#destroy_requested!
            # when running in debug mode (to simulate the destruction but
            # not actually modify the customer record), the tryouts that
            # checked the state of the customer record after destroying
            # will fail (e.g. they expect the passphrase to be removed).

            # We add a message to the session to let the debug user know
            # that we made it to this point in the logic. Otherwise, they
            # might not know if the action was successful or not since we
            # don't actually destroy the account in debug mode.
            sess.set_info_message 'Account deleted'

          else
            cust.destroy_requested!

            # Log the event immediately after saving the change to
            # to minimize the chance of the event not being logged.
            OT.info "[destroy-account] Account destroyed. #{cust.custid} #{cust.role} #{sess.ipaddress}"
          end

          # We replace the session and session ID and then add a message
          # for the user so that when the page they're directed to loads
          # (i.e. the homepage), they'll see it and remember what they did.
          sess.replace!
          sess.set_info_message 'Account deleted'
        end

      end

      def modified? guess
        modified.member? guess
      end

      def success_data
        { custid: @cust.custid }
      end

    end

    class GenerateAPIkey < OT::Logic::Base
      attr_reader :apikey, :greenlighted

      def process_params
      end

      def raise_concerns
        limit_action :generate_apikey

        if (!sess.authenticated?) || (cust.anonymous?)
          raise_form_error "Sorry, we don't support that"
        end
      end

      def process
        @apikey = cust.regenerate_apitoken
        @greenlighted = true
      end

      # The data returned from this method is passed back to the client.
      def success_data
        { record: { apikey: apikey, active: true } }
      end
    end

  end
end
