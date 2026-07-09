# apps/web/billing/controllers/base.rb
#
# frozen_string_literal: true

require 'onetime/helpers/session_helpers'
require 'onetime/controllers/organization_context'

module Billing
  module Controllers
    module Base
      include Onetime::LoggerMethods
      include Onetime::Helpers::SessionHelpers
      include Onetime::Controllers::OrganizationContext

      attr_reader :req, :res, :locale, :region

      def initialize(req, res)
        @req    = req
        @res    = res
        @locale = req.locale
        @region = OT.conf&.dig('features', 'regions', 'current_jurisdiction') || 'LL'

        # Self-healing: Ensure customer has a default workspace
        # This is a background operation - errors are logged but not surfaced to the user
        # since this is not the result of an intentional user action but system self-healing
        ensure_customer_has_workspace
      end

      # Access the current customer from Otto auth middleware or session
      def cust
        @cust ||= load_current_customer
      end

      # Access the current session
      def session
        req.env['rack.session']
      end

      # JSON response helpers
      #
      # These methods return Hash objects that will be serialized by Otto's JSONHandler
      # when the route has response=json. Do not manually set res.body for JSON responses.

      def json_response(data, status: 200)
        res.status = status
        data
      end

      def json_success(message, status: 200)
        json_response({ success: message }, status: status)
      end

      def json_error(message, field_error: nil, status: 400)
        body                = { error: message }
        body['field-error'] = field_error if field_error
        json_response(body, status: status)
      end

      protected

      # Detect region from request
      #
      # @return [String] Region code (default: 'LL')
      def detect_region
        # For Phase 1, default to the configured jurisdiction
        # Future: Use req.env['HTTP_CF_IPCOUNTRY'] or GeoIP database
        region
      end

      # Validates a given URL and ensures it can be safely redirected to.
      #
      # @param url [String] the URL to validate
      # @return [URI::HTTP, nil] the validated URI object if valid, otherwise nil
      def validate_url(url)
        return nil if url.nil? || url.to_s.strip.empty?

        uri = nil
        begin
          uri = URI.parse(url)
        rescue URI::InvalidURIError => ex
          billing_logger.error 'Invalid URI in URL validation',
            {
              exception: ex,
              url: url,
            }
        else
          uri.host ||= OT.conf['site']['host']
          if (OT.conf.dig('site', 'ssl') != false) && (uri.scheme.nil? || uri.scheme != 'https')
            uri.scheme = 'https'
          end
          uri        = nil unless uri.is_a?(URI::HTTP)
          OT.info "[validate_url] Validated URI: #{uri}"
        end

        uri
      end

      # Returns the StrategyResult created by Otto's RouteAuthWrapper
      #
      # @return [Otto::Security::Authentication::StrategyResult]
      def strategy_result
        req.env['otto.strategy_result']
      end

      def load_current_customer
        user = req.user
        return user if user.is_a?(Onetime::Customer)

        nil # Anonymous - return nil
      rescue StandardError => ex
        billing_logger.error 'Failed to load customer',
          {
            exception: ex,
          }
        nil # Error recovery - treat as anonymous
      end

      # Checks if the request accepts JSON responses
      #
      # @return [Boolean] True if the Accept header includes application/json
      def json_requested?
        req.env['HTTP_ACCEPT']&.include?('application/json')
      end

      # Validate Stripe API key is configured
      #
      # Returns error response if Stripe API key is not available.
      # Logs detailed debug info to help diagnose configuration issues.
      #
      # @param context [String] Description of the operation for logging
      # @return [Hash, nil] Error response if key not configured, nil otherwise
      def stripe_api_key_missing?(context = 'Stripe operation')
        return false if Stripe.api_key && !Stripe.api_key.to_s.strip.empty?

        billing_logger.error 'Stripe API key not configured',
          {
            context: context,
            stripe_key_nil: Stripe.api_key.nil?,
            billing_enabled: OT.billing_config.enabled?,
            env_key_present: !ENV.fetch('STRIPE_API_KEY', '').strip.empty?,
            config_key_present: !OT.billing_config.config.fetch('stripe_key', '').to_s.strip.empty?,
          }
        true
      end

      # Duplicate-subscription guard predicate (issue #2605).
      #
      # Issue #2605 replaced the deterministic daily idempotency key on
      # checkout-session creation with a random UUID (correct: sessions are
      # pre-payment and expire on their own). That daily key was, however, the
      # only accidental same-day guard preventing an org from completing two
      # checkouts. Without a real guard, a second completed checkout produces a
      # SECOND live Stripe subscription and the webhook silently overwrites
      # org.stripe_subscription_id — a double charge plus an orphaned, still-live
      # subscription.
      #
      # Returns true when +org+ owns a genuinely active subscription that is NOT
      # winding down — the case in which a NEW checkout session must be blocked.
      #
      # Returns false (checkout allowed) when:
      #   - the org has no genuinely active subscription (new subscriber,
      #     canceled, past_due), including federated orgs that don't own a Stripe
      #     subscription (no stripe_subscription_id);
      #   - a graceful currency migration is pending — the old subscription was
      #     set to cancel_at_period_end and its intent stored, and the new
      #     checkout completes the migration in the target currency;
      #   - the owned subscription is already scheduled to cancel
      #     (cancel_at_period_end) — resubscribe-after-cancel.
      #
      # This predicate is shared by both checkout-creation paths:
      # BillingController#create_checkout_session (responds with a 409 JSON
      # error) and Plans#checkout_redirect (responds with a redirect). The
      # blocking decision lives here; each caller chooses how to respond.
      #
      # @param org [Onetime::Organization] Organization initiating checkout
      # @return [Boolean] true when a new checkout must be blocked
      def org_has_blocking_active_subscription?(org)
        return false unless org.active_subscription?
        return false if org.stripe_subscription_id.to_s.empty?
        return false if org.pending_currency_migration?

        !subscription_scheduled_to_cancel?(org)
      end

      # Whether the org's current Stripe subscription is scheduled to cancel at
      # period end (or is already canceled).
      #
      # Requires a Stripe API call. On a missing key or any Stripe error, returns
      # false (treat as NOT winding down) so the duplicate-subscription guard
      # fails safe toward BLOCKING a possible duplicate charge; the caller can
      # retry once the transient condition clears.
      #
      # @param org [Onetime::Organization] Organization with a stripe_subscription_id
      # @return [Boolean]
      def subscription_scheduled_to_cancel?(org)
        return false if stripe_api_key_missing?('duplicate_subscription_guard')

        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        subscription.cancel_at_period_end == true ||
          subscription.status.to_s == 'canceled'
      rescue Stripe::StripeError => ex
        billing_logger.warn 'Could not verify subscription cancellation state for duplicate-subscription guard',
          {
            extid: org.extid,
            stripe_subscription_id: org.stripe_subscription_id,
            error: ex.message,
          }
        false
      end

      # Ensures customer has a default workspace (self-healing operation)
      #
      # This method is called automatically on billing overview access to ensure
      # every customer has at least one organization. If the customer doesn't have
      # an organization, we create a default one automatically.
      #
      # This is a self-healing operation - any errors are logged but NOT surfaced
      # to the user since this is not the result of an intentional user action.
      #
      # @return [void]
      def ensure_customer_has_workspace
        billing_logger.debug '[ensure_customer_has_workspace] Checking customer workspace'
        return if cust.nil? || cust.anonymous?

        # Use Familia v2 auto-generated reverse collection method for O(1) lookup
        return if cust.organization_instances.any?

        billing_logger.info '[self-healing] Customer has no organization, creating default workspace',
          {
            user: cust.extid,
          }

        # Call CreateDefaultWorkspace operation
        require_relative '../../auth/operations/create_default_workspace'
        result = Auth::Operations::CreateDefaultWorkspace.new(customer: cust).call

        if result
          billing_logger.info '[self-healing] Successfully created default workspace',
            {
              user: cust.extid,
              extid: result[:organization]&.extid,
              team_id: result[:team]&.team_id,
            }
        end
      rescue StandardError => ex
        # Errors are logged but NOT raised - this is a self-healing operation
        # The user experience should continue even if workspace creation fails
        billing_logger.error '[self-healing] Failed to create default workspace',
          {
            exception: ex,
            user: cust.extid,
            message: ex.message,
            backtrace: ex.backtrace&.first(5),
          }
      end

      # Load organization and verify ownership/membership
      #
      # Checks membership first, then falls back to ownership. Owners are
      # always granted access even if their membership entry is missing from
      # the members sorted set (e.g. fresh regions without migration data).
      # When this inconsistency is detected, the membership is self-healed.
      #
      # @param extid [String] Organization external identifier
      # @param require_owner [Boolean] If true, require current user to be owner
      # @return [Onetime::Organization] Loaded organization
      # @raise [Onetime::Forbidden] If organization not found, caller is not a
      #   member, or owner access is required and caller is not an owner.
      #   All three conditions return 403 deliberately: returning 404 for
      #   "organization not found" would let an unauthenticated probe
      #   distinguish real extids from random ones. The handler in
      #   OttoHooks#configure_otto_request_hook renders the ADR-013 wire shape.
      def load_organization(extid, require_owner: false)
        org = Onetime::Organization.find_by_extid(extid)
        raise Onetime::Forbidden, 'Organization not found' unless org

        is_member = org.member?(cust)
        is_owner  = org.owner?(cust)

        unless is_member || is_owner
          billing_logger.warn 'Access denied to organization',
            {
              extid: extid,
              user: cust.extid,
            }
          raise Onetime::Forbidden, 'Access denied'
        end

        # Self-heal: owner exists in org hash but missing from members sorted set.
        # This can happen when a region has no migration data to pre-populate
        # the members set and add_members_instance failed silently during creation.
        if is_owner && !is_member
          billing_logger.info '[self-healing] Re-adding owner to members sorted set',
            {
              extid: extid,
              user: cust.extid,
            }
          begin
            org.add_members_instance(cust, through_attrs: { role: 'owner' })
          rescue StandardError => ex
            billing_logger.error '[self-healing] Failed to re-add owner as member',
              {
                extid: extid,
                user: cust.extid,
                error: ex.message,
                backtrace: ex.backtrace&.first(5),
              }
          end
        end

        if require_owner && !is_owner
          billing_logger.warn 'Owner access required',
            {
              extid: extid,
              user: cust.extid,
            }
          raise Onetime::Forbidden, 'Owner access required'
        end

        org
      end
    end

    class TeaPot
      include Base

      def brew
        res.status = 418
        { message: "I'm a teapot" }
      end
    end
  end
end
