# apps/web/core/controllers/welcome.rb

require_relative 'base'

module Core
  module Controllers
    # Welcome Controller
    #
    # DEPRECATION NOTICE: This controller handles legacy billing routes for
    # backward compatibility. New billing functionality has been moved to
    # apps/web/billing/ (see Billing::Controllers::Plans, Billing::Controllers::Webhooks).
    #
    # Routes being migrated:
    # - GET /plans/:tier/:billing_cycle → /billing/plans/:tier/:billing_cycle
    # - GET /welcome → /billing/welcome
    # - POST /welcome/stripe/webhook → /billing/webhook
    # - GET /account/billing/portal → /billing/portal
    #
    class Welcome
      include Controllers::Base

      # Redirects users to the appropriate Stripe Payment Link based on selected plan
      #
      # This endpoint processes the user's plan selection from the pricing page and
      # redirects them to the corresponding Stripe Payment Link. It handles plan tier
      # and billing cycle selection, and includes relevant customer information in
      # the redirect URL.
      #
      # GET /pricing/:tier/:billing_cycle
      #
      # @param [String] tier The selected plan tier (e.g., 'free', 'identity', 'dedicated')
      # @param [String] billing_cycle The chosen billing frequency (e.g., 'month', 'year')
      #
      # @return [HTTP 302] Redirects to the Stripe Payment Link for the selected plan
      #                    or to '/signup' if the plan configuration is not found
      #
      # @note This endpoint is noauth accessible and handles both anonymous and
      #       authenticated users. For authenticated users, it pre-fills the email
      #       in the Stripe checkout process.
      #
      # @see OT.conf['billing']['payment_links'] For the configuration of Stripe Payment Links
      #
      # @see https://docs.stripe.com/api/payment-link/object For API reference
      #
      def plan_redirect
          # We take the tier and billing cycle from the URL path and try to
          # get the preconfigured Stripe payment links using those values.
          tierid        = req.params[:tier] ||= 'free'
          billing_cycle = req.params[:billing_cycle] ||= 'month' # year or month

          billing       = OT.conf['billing']
          payment_links = billing.fetch('payment_links', {})
          payment_link  = payment_links.dig(tierid, billing_cycle)

          http_logger.debug "Plan redirect request", {
            tierid: tierid,
            billing_cycle: billing_cycle,
            payment_link: payment_link
          }

          validated_url = validate_url(payment_link)

          unless validated_url
            http_logger.warn "Unknown plan configuration - redirecting to signup", {
              tierid: tierid,
              billing_cycle: billing_cycle
            }
            raise OT::Redirect.new('/signup')
          end

          http_logger.info "Plan clicked - redirecting to Stripe", {
            tierid: tierid,
            billing_cycle: billing_cycle,
            url: validated_url.to_s
          }

          stripe_params = {
            # rack.locale is a list, often with just a single locale (e.g. `[en]`).
            # When calling `encode_www_form` the list gets expanded into N query
            # parameters where N is the number of elements in the list. So a list
            # with 2 items `[en, en-US]` becomes `locale=en&locale=en-US`.
            locale: req.env['rack.locale'],
          }

          # Adding the existing customer details streamlines the payment flow
          # by prepolulating the email address.
          #
          # For testing Adaptive Pricing, pass a "location-formatted email" as
          # the prefilled_email to simulate currency presentment for customers in
          # different countries. e.g. `test+location_FR@example.com` where FR is
          # a two-charactor ISO country code. https://www.iso.org/obp/ui/#search
          #
          unless cust.anonymous?
            stripe_params[:prefilled_email]     = cust.custid
            stripe_params[:client_reference_id] = ''
          end

          # Apply the query parameters back to the URI::HTTP object
          validated_url.query = URI.encode_www_form(stripe_params)
          http_logger.debug "Updated Stripe URL with query parameters", {
            query: validated_url.query
          }
          res.redirect validated_url.to_s # convert URI::Generic to a string
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
      # @see V2::Logic::Welcome::FromStripePaymentLink For the business logic implementation
      #
      # @note This endpoint is noauth accessible and sets a secure session cookie
      #       if the site is configured to use SSL
      #
      # e.g. https://staging.onetimesecret.com/welcome?checkout={CHECKOUT_SESSION_ID}
      #
      def welcome
        logic = V2::Logic::Welcome::FromStripePaymentLink.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        @cust = logic.cust

        # Session cookie handled by Rack::Session middleware

        res.redirect '/account'
      end

      # Receives users from the Stripe Webhook after a successful payment for a new
      # subscription. The redirect can optionally include a CHECKOUT_SESSION_ID which
      # allows this webhook to call the Stripe API for the checkout details.
      #
      # e.g. https://onetimesecret.com/welcome?checkout={CHECKOUT_SESSION_ID}
      #
      # @see https://docs.stripe.com/payment-links/post-payment#change-confirmation-behavior
      #
      def welcome_webhook
        # CSRF exemption handled by route parameter csrf=exempt
        logic = V2::Logic::Welcome::StripeWebhook.new(strategy_result, req.params, locale)
        logic.stripe_signature = req.env['HTTP_STRIPE_SIGNATURE']
        logic.payload = req.body.read
        logic.raise_concerns
        logic.process

        res.status = 200
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
        res.do_not_cache!

        # Get the Stripe Customer ID from our customer instance
        customer_id = cust.stripe_customer_id

        site_host   = Onetime.conf['site']['host']
        is_secure   = Onetime.conf['site']['ssl']
        return_url  = "#{is_secure ? 'https' : 'http'}://#{site_host}/account"

        # Create a Stripe Customer Portal session
        stripe_session = Stripe::BillingPortal::Session.create({
          customer: customer_id,
          return_url: return_url,
        })

        # Continue the redirect
        res.redirect stripe_session.url

      rescue Stripe::StripeError => ex
            http_logger.error "Stripe customer portal creation failed", {
              exception: ex,
              customer_id: customer_id
            }
            raise_form_error(ex.message)
      rescue StandardError => ex
            http_logger.error "Unexpected error creating customer portal session", {
              exception: ex
            }
            raise_form_error('An unexpected error occurred')
      end
    end
  end
end
