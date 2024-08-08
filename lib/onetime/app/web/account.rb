# frozen_string_literal: true

module Onetime
  class App # rubocop:disable

    def translations
      publically do
        view = Onetime::App::Views::Translations.new req, sess, cust, locale
        res.body = view.render
      end
    end

    def contributors # rubocop:disable Metrics/PerceivedComplexity, Metrics/AbcSize
      publically do # rubocop:disable Metrics/BlockLength
        if !sess.authenticated? && req.post?
          sess.set_error_message "You'll need to sign in before agreeing."
          res.redirect '/signin'
        end
        if sess.authenticated? && req.post?
          if cust.contributor?
            sess.set_info_message "You are already a contributor!"
            res.redirect "/"
          else
            if !req.params[:contributor].to_s.empty? # rubocop:disable Style/NegatedIfElseCondition
              if !cust.contributor_at
                cust.contributor = req.params[:contributor]
                cust.contributor_at = Onetime.now.to_i unless cust.contributor_at
                cust.save
              end
              sess.set_info_message "You are now a contributor!"
              res.redirect "/"
            else
              sess.set_error_message "You need to check the confirm box."
              res.redirect '/contributor'
            end
          end
        else
          view = Onetime::App::Views::Contributor.new req, sess, cust, locale
          res.body = view.render
        end
      end
    end

    # Redirects users to the appropriate Stripe Payment Link based on selected plan
    #
    # This endpoint processes the user's plan selection from the pricing page and
    # redirects them to the corresponding Stripe Payment Link. It handles plan tier
    # and billing cycle selection, and includes relevant customer information in
    # the redirect URL.
    #
    # GET /pricing/:tier/:billing_cycle
    #
    # @param [String] tier The selected plan tier (e.g., 'free', 'pro', 'business')
    # @param [String] billing_cycle The chosen billing frequency (e.g., 'month', 'year')
    #
    # @return [HTTP 302] Redirects to the Stripe Payment Link for the selected plan
    #                    or to '/signup' if the plan configuration is not found
    #
    # @note This endpoint is publicly accessible and handles both anonymous and
    #       authenticated users. For authenticated users, it pre-fills the email
    #       in the Stripe checkout process.
    #
    # @see OT.conf[:site][:plans][:payment_links] For the configuration of Stripe Payment Links
    #
    def plan_redirect
      publically do
        # We take the tier and billing cycle from the URL path and try to
        # get the preconfigured Stripe payment links using those values.
        tierid = req.params[:tier] ||= 'free'
        billing_cycle = req.params[:billing_cycle] ||= 'month'

        plans = OT.conf.dig(:site, :plans)
        payment_links = plans.fetch(:payment_links, {})
        payment_link = payment_links.dig(tierid.to_sym, billing_cycle.to_sym)

        OT.ld "[plan_redirect] plans: #{plans}"
        OT.ld "[plan_redirect] payment_links: #{payment_links}"
        OT.ld "[plan_redirect] payment_link: #{payment_link}"

        validated_url = validate_url(payment_link)

        unless validated_url
          OT.le "[plan_redirect] Unknown #{tierid}/#{billing_cycle}. Sending to /signup"
          raise OT::Redirect.new('/signup')
        end

        OT.info "[plan_redirect] Clicked #{tierid} per #{billing_cycle} (redirecting to #{validated_url})"

        stripe_params = {
          # rack.locale is a list, often with just a single locale (e.g. `[en]`).
          # When calling `encode_www_form` the list gets expanded into N query
          # parameters where N is the number of elements in the list. So a list
          # with 2 items `[en, en-US]` becomes `locale=en&locale=en-US`.
          locale: req.env['rack.locale']
        }

        # Adding the existing customer details streamlines the payment flow
        # by prepolulating the email address.
        unless cust.anonymous?
          stripe_params[:prefilled_email] = cust.custid
          stripe_params[:client_reference_id] = ''
        end

        # Apply the query parameters back to the URI::HTTP object
        validated_url.query = URI.encode_www_form(stripe_params)
        OT.info "[plan_redirect] Updated query parameters: #{validated_url.query}"
        res.redirect validated_url.to_s # convert URI::Generic to a string
      end
    end

    # Handles the redirect from Stripe Payment Links after a successful payment
    #
    # This endpoint processes the customer's payment information and sets up their account
    # after they've completed a purchase through a Stripe Payment Link.
    #
    # GET /welcome?checkout={CHECKOUT_SESSION_ID}
    #
    # @param [String] checkout The Stripe Checkout Session ID passed as a query parameter
    #
    # @return [HTTP 302] Redirects to the user's account page upon successful processing
    #
    # @see OT::Logic::Welcome::FromStripePaymentLink For the business logic implementation
    #
    # @note This endpoint is publicly accessible and sets a secure session cookie
    #       if the site is configured to use SSL
    #
    # e.g. https://staging.onetimesecret.com/welcome?checkout={CHECKOUT_SESSION_ID}
    #
    def welcome
      publically do
        logic = OT::Logic::Welcome::FromStripePaymentLink.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process

        @cust = logic.cust

        is_secure = Onetime.conf[:site][:ssl]
        res.send_cookie :sess, sess.sessid, sess.ttl, is_secure

        res.redirect '/account'
      end
    end

    def welcome_webhook
      @ignoreshrimp = true
      # But should check webhook signing secret
      publically do
        logic = OT::Logic::Welcome::StripeWebhook.new sess, cust, req.params, locale
        logic.stripe_signature = req.env['HTTP_STRIPE_SIGNATURE']
        logic.payload = req.body.read
        logic.raise_concerns
        logic.process

        res.status = 200
      end
    end

    # Redirects authenticated users to the Stripe Customer Portal
    #
    # This endpoint creates a Stripe Customer Portal session for the authenticated user
    # and redirects them to manage their subscription, billing information, and payment methods.
    #
    # GET /account/billing_portal
    #
    # @return [HTTP 302] Redirects to the Stripe Customer Portal if successful
    # @return [HTTP 400] Returns a form error if there's a Stripe error or unexpected issue
    #
    # @note This endpoint requires authentication. It uses the customer's Stripe Customer ID
    #       stored in our system to create the portal session.
    #
    # @see https://stripe.com/docs/billing/subscriptions/customer-portal For more information on Stripe Customer Portal
    #
    # @example
    #   GET /account/billing
    #   # => Redirects to https://billing.stripe.com/session/...
    #
    # @raise [OT::FormError] If there's an error creating the Stripe session or an unexpected error occurs
    #
    def customer_portal_redirect
      authenticated do
        begin
          # Get the Stripe Customer ID from our customer instance
          customer_id = cust.stripe_customer_id

          site_host = Onetime.conf[:site][:host]
          is_secure = Onetime.conf[:site][:ssl]
          return_url = "#{is_secure ? 'https' : 'http'}://#{site_host}/account"

          # Create a Stripe Customer Portal session
          session = Stripe::BillingPortal::Session.create({
                                                            customer: customer_id,
            return_url: return_url
                                                          })

          # Continue the redirect
          res.redirect session.url

        rescue Stripe::StripeError => e
          OT.le "[customer_portal_redirect] Stripe error: #{e.message}"
          raise_form_error(e.message)

        rescue => e
          OT.le "[customer_portal_redirect] Unexpected error: #{e.message}"
          raise_form_error('An unexpected error occurred')
        end
      end
    end

    def pricing
      publically do
        view = Onetime::App::Views::Pricing.new req, sess, cust, locale
        view[:business] = true
        res.body = view.render
      end
    end

    def signup
      publically do
        unless _auth_settings[:enabled] && _auth_settings[:signup]
          return disabled_response(req.path)
        end

        # If a plan has been selected, the next onboarding step is the actual signup
        if OT::Plan.plan?(req.params[:planid])
          sess.set_error_message "You're already signed up" if sess.authenticated?
          view = Onetime::App::Views::Signup.new req, sess, cust, locale

          # For signup pages that include a call-to-action regarding other
          # plan options, we want to hide it when the user is already on a
          # page for a specific plan.
          view[:hide_cta] = true

          res.body = view.render

        # Otherwise we default to showing the various account plans available
        else
          view = Onetime::App::Views::Signup.new req, sess, cust, locale
          res.body = view.render

        end
      end
    end

    def create_account
      publically do
        unless _auth_settings[:enabled] && _auth_settings[:signup]
          return disabled_response(req.path)
        end
        deny_agents!
        logic = OT::Logic::Account::CreateAccount.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        if logic.autoverify
          sess = logic.sess
          cust = logic.cust
        end
        res.redirect '/'
      end
    end

    def login
      publically do
        res.redirect '/signin'
      end
    end

    def signin
      publically do
        unless _auth_settings[:enabled] && _auth_settings[:signin]
          return disabled_response(req.path)
        end
        view = Onetime::App::Views::Signin.new req, sess, cust, locale
        res.body = view.render
      end
    end

    def authenticate # rubocop:disable Metrics/AbcSize
      publically do
        unless _auth_settings[:enabled] && _auth_settings[:signin]
          return disabled_response(req.path)
        end
        # If the request is halted, say for example rate limited, we don't want to
        # allow the browser to refresh and re-submit the form with the login
        # credentials.
        no_cache!
        logic = OT::Logic::Account::AuthenticateSession.new sess, cust, req.params, locale
        view = Onetime::App::Views::Signin.new req, sess, cust, locale
        if sess.authenticated?
          sess.set_info_message "You are already logged in."
          res.redirect '/'
        else
          if req.post? # rubocop:disable Style/IfInsideElse
            logic.raise_concerns
            logic.process
            sess = logic.sess
            cust = logic.cust
            is_secure = Onetime.conf[:site][:ssl]
            res.send_cookie :sess, sess.sessid, sess.ttl, is_secure
            if cust.role?(:colonel)
              res.redirect '/colonel/'
            else
              res.redirect '/'
            end
          else
            view.cust = OT::Customer.anonymous
            res.body = view.render
          end
        end
      end
    end

    def logout
      authenticated do
        logic = OT::Logic::DestroySession.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        res.redirect app_path('/')
      end
    end

    def account
      authenticated do
        logic = OT::Logic::Account::ViewAccount.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process

        view = Onetime::App::Views::Account.new req, sess, cust, locale
        if view[:plans_enabled]
          subscriptions = [logic.stripe_subscription].compact
          view[:jsvars] << view.jsvar(:stripe_customer, logic.stripe_customer)
          view[:jsvars] << view.jsvar(:stripe_subscriptions, subscriptions)
        end

        res.body = view.render
      end
    end

    def forgot
      publically do
        if req.params[:key]
          secret = OT::Secret.load req.params[:key]
          if secret.nil? || secret.verification.to_s != 'true'
            raise OT::MissingSecret if secret.nil?
          else
            view = Onetime::App::Views::Forgot.new req, sess, cust, locale
            view[:verified] = true
            res.body = view.render
          end
        else
          view = Onetime::App::Views::Forgot.new req, sess, cust, locale
          res.body = view.render
        end
      end
    end

    def request_reset
      publically do
        if req.params[:key]
          logic = OT::Logic::Account::ResetPassword.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect '/signin'
        else
          logic = OT::Logic::Account::ResetPasswordRequest.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect '/'
        end
      end
    end

    private
    def _auth_settings
      OT.conf.dig(:site, :authentication)
    end

  end
end
