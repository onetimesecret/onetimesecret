# apps/web/core/controllers/welcome.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    # Welcome Controller
    #
    # DEPRECATION NOTICE: This controller handles legacy billing routes for
    # backward compatibility. New billing functionality has been moved to
    # apps/web/billing/ (see Billing::Controllers::Plans, Billing::Controllers::Webhooks).
    #
    # Legacy routes handled here redirect to the billing app:
    # - GET /plans/:tier/:billing_cycle -> /billing/plans/:product/:interval
    # - GET /welcome -> reported and redirected home; the Stripe Payment
    #   Link flow it served was retired (#4212)
    # - GET /account/billing/portal -> /billing/portal
    #
    class Welcome
      include Controllers::Base

      # Maps legacy tier names (v0.23) to current product IDs (v0.24).
      # Add entries here when renaming tiers to maintain backward compatibility
      # with existing external links (e.g., from the static pricing page).
      LEGACY_TIER_MAP = {
        'identity' => 'identity_plus_v1',
        'dedicated' => 'identity_plus_v1',
      }.freeze

      # Maps short billing cycle names to the interval format expected
      # by PlanResolver (which accepts 'monthly'/'yearly').
      BILLING_CYCLE_MAP = {
        'month' => 'monthly',
        'monthly' => 'monthly',
        'year' => 'yearly',
        'yearly' => 'yearly',
      }.freeze

      # Redirects users to the billing checkout for the selected plan
      #
      # This legacy endpoint handles plan selection URLs from the static pricing
      # page and redirects to the v0.24 billing checkout flow. It maps old-style
      # tier names (e.g., 'identity') to current product IDs (e.g., 'identity_plus_v1')
      # and normalizes billing cycle names (e.g., 'month' to 'monthly').
      #
      # GET /plans/:tier/:billing_cycle
      #
      # @param [String] tier The selected plan tier (e.g., 'identity', 'dedicated')
      # @param [String] billing_cycle The chosen billing frequency ('month' or 'year')
      #
      # @return [HTTP 302] Redirects to /billing/plans/:product/:interval for checkout
      #                    or to '/pricing' if the tier is not recognized
      #
      # @note This endpoint is noauth accessible. The billing checkout endpoint
      #       handles customer identification and Stripe session creation.
      #
      # @see Billing::Controllers::Plans#checkout_redirect For the checkout flow
      #
      def plan_redirect
        tierid        = req.params['tier'] ||= 'free'
        billing_cycle = req.params['billing_cycle'] ||= 'month'

        # Map legacy tier names to current product IDs. This allows old URLs
        # from the static pricing page (e.g., /plans/identity/month) to route
        # to the correct v0.24 checkout flow.
        product = LEGACY_TIER_MAP[tierid]

        # Normalize billing cycle to the interval format expected by the
        # billing checkout endpoint (month -> monthly, year -> yearly).
        interval = BILLING_CYCLE_MAP[billing_cycle]

        http_logger.debug 'Legacy plan redirect',
          {
            tierid: tierid,
            billing_cycle: billing_cycle,
            resolved_product: product,
            resolved_interval: interval,
          }

        unless product && interval
          http_logger.warn 'Unrecognized plan tier or billing cycle - redirecting to pricing',
            {
              tierid: tierid,
              billing_cycle: billing_cycle,
            }
          res.redirect '/pricing'
          return
        end

        http_logger.info 'Plan redirect to billing checkout',
          {
            tierid: tierid,
            billing_cycle: billing_cycle,
            product: product,
            interval: interval,
          }

        res.redirect "/billing/plans/#{product}/#{interval}"
      end

      # Reports a hit on the retired Stripe Payment Link landing page
      #
      # Payment Links were the pre-2026 purchase flow: Stripe redirected the
      # buyer here with ?checkout={CHECKOUT_SESSION_ID} and this endpoint
      # provisioned them from the checkout session — including creating an
      # unverified account when the checkout email had none. The links are no
      # longer active and nothing issues this URL any more, so the
      # provisioning was removed along with
      # Billing::Logic::Welcome::FromStripePaymentLink (#4212).
      #
      # GET /welcome
      #
      # The route stays because a stale link can still sit in a bookmark or an
      # old receipt email. Every hit is reported rather than served, carrying
      # the checkout id when one is present, so a Payment Link unexpectedly
      # still live in the wild is visible immediately: the
      # checkout.session.completed webhook cannot cover for one, because
      # Payment Link subscriptions carry no customer_extid metadata and
      # Billing::Operations::WebhookHandlers::CheckoutCompleted skips them.
      #
      # @return [HTTP 302] Redirects to the homepage
      #
      def welcome
        domain_strategy     = strategy_result.metadata[:domain_strategy]
        checkout_session_id = req.params['checkout'].to_s.strip

        capture_message('Welcome page accessed after Payment Link retirement', :error) do |scope|
          scope.set_context(
            'request',
            {
              domain_strategy: domain_strategy,
              path: req.path,
              query_string: req.query_string,
              referrer: sanitized_referrer,
              # A Stripe object id, not customer data: the one field support
              # needs to reconcile a payment this endpoint no longer applies.
              checkout_session_id: checkout_session_id.empty? ? nil : checkout_session_id,
            },
          )
        end

        # Show flash message unless custom domain (would confuse users about which support to contact)
        unless domain_strategy == :custom
          session['error_message'] = 'It looks like you were redirected here but something went wrong. Please contact support.'
        end

        res.redirect req.app_path('/')
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
        is_secure   = Onetime.conf.dig('site', 'ssl') != false
        return_url  = "#{is_secure ? 'https' : 'http'}://#{site_host}/account"

        # Create a Stripe Customer Portal session
        stripe_session = Stripe::BillingPortal::Session.create(
          {
            customer: customer_id,
            return_url: return_url,
          },
        )

        # Continue the redirect
        res.redirect stripe_session.url
      rescue Stripe::StripeError => ex
            http_logger.error 'Stripe customer portal creation failed',
              {
                exception: ex,
                customer_id: customer_id,
              }
            raise_form_error(ex.message)
      rescue StandardError => ex
            http_logger.error 'Unexpected error creating customer portal session',
              {
                exception: ex,
              }
            raise_form_error('An unexpected error occurred')
      end

      private

      # The Referer header is user-controlled and may carry tokens or PII in its
      # query string / fragment (and can be arbitrarily long), so strip both and
      # cap the length before the value is sent to Sentry telemetry.
      def sanitized_referrer
        referrer = req.env['HTTP_REFERER'].to_s
        return if referrer.empty?

        referrer.split(/[?#]/, 2).first.to_s[0, 256]
      end
    end
  end
end
