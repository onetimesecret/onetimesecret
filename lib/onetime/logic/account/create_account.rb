

module Onetime::Logic
  module Account

    class CreateAccount < OT::Logic::Base
      attr_reader :cust, :plan, :autoverify, :customer_role
      attr_reader :planid, :custid, :password, :password2, :skill
      attr_accessor :token

      def process_params
        OT.ld "[CreateAccount#process_params] params: #{params.inspect}"
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
        sess.custid = cust.custid
        sess.save

        @customer_role = if OT.conf[:colonels].member?(cust.custid)
                           'colonel'
                         else
                           'customer'
                         end
        cust.planid = @plan.planid
        cust.verified = @autoverify.to_s
        cust.role = @customer_role.to_s
        cust.save

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
        _, secret = Onetime::Secret.spawn_pair cust.custid, token

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

  end
end
