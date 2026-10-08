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
        # Only a value shaped like a Stripe Checkout Session id is reported.
        # The param is caller-controlled on an unauthenticated route, so
        # anything else is treated as absent; param_keys below still records
        # that a checkout param was present.
        raw_checkout_id     = req.params['checkout'].to_s.strip
        checkout_session_id = raw_checkout_id.match?(/\Acs_(test|live)_[A-Za-z0-9]+\z/) ? raw_checkout_id : nil

        capture_message('Welcome page accessed after Payment Link retirement', :error) do |scope|
          scope.set_context(
            'request',
            {
              domain_strategy: domain_strategy,
              path: req.path,
              # Parameter names only, never values: the route is
              # unauthenticated, so values can carry whatever a caller put in
              # the URL (emails, tokens). The shape is enough to recognize a
              # malformed Payment Link redirect.
              param_keys: req.params.keys.sort,
              referrer: sanitized_referrer,
              # A Stripe object id, not customer data: the one field support
              # needs to reconcile a payment this endpoint no longer applies.
              checkout_session_id: checkout_session_id,
            },
          )
        end

        # Show flash message unless custom domain (would confuse users about which support to contact)
        unless domain_strategy == :custom
          session['error_message'] = 'It looks like you were redirected here but something went wrong. Please contact support.'
        end

        res.redirect req.app_path('/')
      end

      # Legacy entry point for the Stripe Customer Portal
      #
      # GET /account/billing_portal
      #
      # Billing identities live on the Organization now; the customer-level
      # stripe_customer_id this handler used to read is a deprecated migration
      # field that is empty for every account created since the move, so the
      # inline Stripe call failed for them — and its rescue branches called
      # raise_form_error, which controllers do not define, turning every
      # failure into a 500. Hand the request to the organization-aware portal
      # route instead; it carries the ownership gate and the "no Stripe
      # customer yet" handling in one place (Billing::Controllers::Plans).
      #
      # @return [HTTP 302] Redirect to /billing/portal
      #
      def customer_portal_redirect
        res.do_not_cache!
        res.redirect '/billing/portal'
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
