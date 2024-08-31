
require_relative 'base'
require_relative '../refinements/stripe_refinements'

module Onetime::Logic
  module Account

    class ViewAccount < OT::Logic::Base
      attr_reader :plans_enabled
      attr_reader :stripe_subscription, :stripe_customer
      using Onetime::StripeRefinements

      def process_params
        site = OT.conf.fetch(:site, {})
        @plans_enabled = site.dig(:plans, :enabled) || false
      end

      def raise_concerns
        limit_action :show_account

      end

      def process

        if plans_enabled

          @stripe_customer = cust.get_stripe_customer
          @stripe_subscription = cust.get_stripe_subscription

          # Rudimentary normalization to make sure that all Onetime customers
          # that have a stripe customer and subscription record, have the
          # RedisHash fields stripe_customer_id and stripe_subscription_id
          # fields populated. The subscription section on the account screen
          # depends on these ID fields being populated.
          if stripe_customer
            OT.info "Recording stripe customer ID"
            cust.stripe_customer_id = stripe_customer.id
          end

          if stripe_subscription
            OT.info "Recording stripe subscription ID"
            cust.stripe_subscription_id = stripe_subscription.id
          end

          # Just incase we didn't capture the Onetime Secret planid update after
          # a customer subscribes, let's make sure we update it b/c it doesn't
          # feel good to pay for something and still see "Basic Plan" at the
          # top of your account page.
          if stripe_subscription && stripe_subscription.plan
            cust.planid = 'identity' # TOOD: obviously find a better way
          end

          cust.save
        end
      end

      def show_stripe_section?
        plans_enabled && !stripe_customer.nil?
      end

      def safe_stripe_customer_dump
        return nil if stripe_customer.nil?
        safe_customer_data = {
          id: stripe_customer.id,
          email: stripe_customer.email,
          description: stripe_customer.description,
          balance: stripe_customer.balance,
          created: stripe_customer.created,
          metadata: stripe_customer.metadata
        }
      end

      def safe_stripe_subscription_dump
        return nil if stripe_subscription.nil?
        safe_subscription_data = {
          id: stripe_subscription.id,
          status: stripe_subscription.status,
          current_period_end: stripe_subscription.current_period_end,
          items: stripe_subscription.items,
          plan: {
            id: stripe_subscription.plan.id,
            amount: stripe_subscription.plan.amount,
            currency: stripe_subscription.plan.currency,
            interval: stripe_subscription.plan.interval,
            product: stripe_subscription.plan.product
          }
        }
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

    class UpdateAccount < OT::Logic::Base
      attr_reader :modified, :greenlighted

      def process_params
        @currentp = self.class.normalize_password(params[:currentp])
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
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
      end

      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          @greenlighted = true
          OT.info "[update-account] Password updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          cust.update_passphrase! @newp
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
