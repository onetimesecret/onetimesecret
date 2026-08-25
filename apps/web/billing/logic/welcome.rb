# apps/web/billing/logic/welcome.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'
require_relative '../lib/checkout_target_resolver'

module Billing
  module Logic
    module Welcome
      # Processes checkout session redirect from Stripe
      #
      # Handles the redirect after a customer completes checkout via
      # Billing::Controllers::Plans (using ?session_id= parameter).
      # Retrieves the full checkout session with expanded subscription,
      # finds/creates the customer's organization, and updates billing.
      #
      # @note This is used by /billing/welcome endpoint
      #
      class ProcessCheckoutSession < Onetime::Logic::Base
        include Onetime::LoggerMethods

        LOG_LABEL = '[ProcessCheckoutSession]'

        attr_reader :session_id,
          :checkout_session,
          :subscription,
          :stripe_customer_id,
          :target_organization

        def process_params
          @session_id = params['session_id']
        end

        def raise_concerns
          raise_form_error 'No session_id provided' unless session_id

          # Validate checkout session ID format (Stripe uses cs_test_ or cs_live_ prefix)
          unless session_id.match?(/\Acs_(test|live)_/)
            raise_form_error 'Invalid checkout session ID format'
          end

          # Only the subscription is expanded. Expanding `customer` turned
          # checkout_session.customer into a Stripe::Customer, and
          # Billing::CheckoutTargetResolver requires a 'cus_' String — so its
          # step 2 (prior-binding lookup) and the stripe_claim_fields
          # unique-index claim silently never applied on this surface.
          @checkout_session = Stripe::Checkout::Session.retrieve(
            {
              id: session_id,
              expand: %w[subscription],
            },
          )
          raise_form_error 'Invalid checkout session' unless checkout_session

          @subscription = checkout_session.subscription
          # NOTE: subscription may be nil for one-time payments

          # Normalize at the retrieve boundary, not at each call site: the
          # resolver's strict String contract is what caught the expanded-object
          # bug and stays strict, so exactly one place in this class is allowed
          # to hold a Stripe-shaped customer.
          @stripe_customer_id = extract_stripe_customer_id(checkout_session.customer)
        end

        def process
          return success_data unless subscription

          # Fail closed HERE, not in raise_concerns: raise_concerns runs before
          # we know the session's mode, and one-time payments legitimately have
          # no billing workspace to bind (they return above). Past this line the
          # subscription branch is taken, and every path below it either
          # resolves or CREATES an organization — so an unidentifiable Stripe
          # customer must stop the request rather than mint a workspace with no
          # claim on it, which is what silently disables replay resolution and
          # the concurrent-creation election.
          unless stripe_customer_id&.start_with?('cus_')
            billing_logger.error "#{LOG_LABEL} Checkout session has no valid Stripe customer",
              session_id: session_id
            raise_form_error 'Checkout session has no valid Stripe customer'
          end

          metadata        = subscription.metadata
          customer_extid  = metadata['customer_extid']
          orgid           = metadata['orgid']
          plan_id         = metadata['plan_id']

          OT.info '[ProcessCheckoutSession] Processing checkout',
            {
              session_id: session_id,
              customer_extid: customer_extid,
              orgid: orgid,
              plan_id: plan_id,
              subscription_id: subscription.id,
            }

          # Load the actual customer from metadata (session may be anonymous after Stripe redirect)
          # The customer_extid was embedded in subscription metadata when checkout was created
          customer = Onetime::Customer.find_by_extid(customer_extid)
          unless customer
            billing_logger.error '[ProcessCheckoutSession] Customer not found', extid: customer_extid
            raise_form_error 'Customer not found'
          end

          # Find the target organization from metadata (the org that initiated checkout)
          # This ensures the correct org gets upgraded, not just the customer's default
          @target_organization = find_target_organization(customer, metadata)

          # Update organization with subscription details (extracts planid, etc.)
          @target_organization.update_from_stripe_subscription(subscription)

          OT.info '[ProcessCheckoutSession] Organization subscription activated',
            {
              orgid: @target_organization.objid,
              extid: @target_organization.extid,
              subscription_id: subscription.id,
              plan_id: @target_organization.planid,
            }

          success_data
        end

        def success_data
          {
            session_id: session_id,
            success: true,
            org_extid: @target_organization&.extid,
          }
        end

        private

        # Find the target organization for this checkout
        #
        # Steps 1-3 (resolve an EXISTING org) live in
        # Billing::CheckoutTargetResolver, shared with the
        # checkout.session.completed webhook handler, which processes the same
        # checkout and must not disagree about its target. That shared module
        # also documents why ownership is required at step 3 and nowhere else,
        # and why archived status is rejected at step 1 but not at step 2.
        # Step 4 — what to create when nothing resolves — stays here because
        # the two handlers genuinely differ (see below).
        #
        # @param customer [Onetime::Customer] The customer
        # @param metadata [Stripe::StripeObject] Subscription metadata
        # @return [Onetime::Organization] The target organization
        def find_target_organization(customer, metadata)
          org = ::Billing::CheckoutTargetResolver.resolve(
            customer: customer,
            metadata: metadata,
            stripe_customer_id: stripe_customer_id,
            logger: billing_logger,
            label: LOG_LABEL,
          )
          return org if org

          # 4. Create (self-healing fallback — no owned, live org to apply this
          # paid subscription to).
          #
          # Divergence from the webhook twin
          # (CheckoutCompleted#find_target_organization), which tries
          # CreateDefaultWorkspace first and so claims a pending federated
          # subscription that this path skips. Not deliberate — see the
          # FEDERATION GAP note there for the mechanism, and #4212 for the
          # unification this is waiting on.
          billing_logger.warn "#{LOG_LABEL} Creating default org during checkout (unexpected)",
            extid: customer.extid
          ::Billing::CheckoutTargetResolver.create_billing_workspace(
            customer,
            logger: billing_logger,
            label: LOG_LABEL,
            stripe_customer_id: stripe_customer_id,
          )
        end

        # The checkout's Stripe customer as a plain id.
        #
        # Stripe hands this field back in two shapes depending on the request:
        # a 'cus_' String, or a Stripe::Customer when the caller expands it.
        # Nothing here expands it any more, but fixtures, an API-version change
        # or a future caller can reintroduce the object, so both are accepted.
        #
        # Anything else returns nil on purpose. to_s-ing an unknown object
        # manufactures a claim string that is not a Stripe customer id, which
        # would take the unique index under a bogus value instead of failing.
        #
        # The webhook twin (WebhookHandlers::CheckoutCompleted) needs no such
        # extractor: it reads event.data.object.customer from the delivered
        # payload, which Stripe never expands, so it is always a String there.
        # Hoisting this to Billing:: would be shared code for one caller.
        #
        # @param customer [String, Stripe::Customer, nil]
        # @return [String, nil]
        def extract_stripe_customer_id(customer)
          case customer
          when String then customer
          when Stripe::Customer then customer.id
          end
        end
      end
    end
  end
end
