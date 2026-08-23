# apps/web/billing/logic/welcome.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'
require_relative '../../auth/operations/create_default_workspace'
require_relative '../lib/checkout_target_resolver'

module Billing
  module Logic
    module Welcome
      # Handles redirect from Stripe Payment Links after successful payment
      #
      # This logic class associates the Stripe checkout session with the
      # customer's account and updates their organization's billing details
      # (planid, subscription status, etc.) after completing a purchase.
      #
      # @note The external API remains unchanged: GET /welcome?checkout={ID}
      #
      class FromStripePaymentLink < Onetime::Logic::Base
        include Onetime::LoggerMethods

        attr_reader :checkout_session_id,
          :checkout_session,
          :checkout_email,
          :update_customer_fields,
          :stripe_subscription

        def process_params
          @checkout_session_id = params['checkout']
        end

        def raise_concerns
          raise_form_error 'No Stripe checkout_session_id' unless checkout_session_id

          # Use expand to fetch subscription in a single API call
          @checkout_session = Stripe::Checkout::Session.retrieve(
            {
              id: checkout_session_id,
              expand: ['subscription'],
            },
          )
          raise_form_error 'Invalid Stripe checkout session' unless checkout_session

          # The full subscription object is now available via expand
          @stripe_subscription = checkout_session.subscription

          @checkout_email         = checkout_session.customer_details.email
          @update_customer_fields = {
            stripe_checkout_email: checkout_email,
            stripe_subscription_id: stripe_subscription&.id,
            stripe_customer_id: checkout_session.customer,
          }
        end

        def process
          if @sess['authenticated'] == true
            # If the user is already authenticated, we can associate the checkout
            # session with their account - but only if emails match.

            unless checkout_email.eql?(cust.email)
              # Security: Don't link checkout to a different account than checkout_email
              billing_logger.error '[FromStripePaymentLink] Email mismatch: checkout email differs from authenticated user', customer: cust.obscure_email
              raise_form_error 'Please log out first to complete checkout with a different email address'
            end

            OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with authenticated user #{cust.obscure_email}"

            fields_to_update = preserve_existing_stripe_customer_id(cust, update_customer_fields.dup)
            cust.apply_fields(**fields_to_update).commit_fields

            # Update organization billing from subscription (extracts planid, etc.)
            update_organization_billing(cust)

          else
            # If the user is not authenticated, check if the email address is already
            # associated with an account. If not, we can create a new account for them
            # using the email address from the checkout session.
            cust = Onetime::Customer.load(checkout_email)

            if cust
              # If the email address is already associated with an account, we can
              # associate the checkout session with that account and then direct
              # them to sign in.

              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with existing user #{cust.obscure_email}"

              fields_to_update = preserve_existing_stripe_customer_id(cust, update_customer_fields.dup)
              cust.apply_fields(**fields_to_update).commit_fields

              # Update organization billing from subscription (extracts planid, etc.)
              update_organization_billing(cust)

              raise OT::Redirect.new('/signin')
            else
              # Security: Create account but require email verification before login.
              # This prevents an attacker from using victim's email in checkout
              # and gaining immediate authenticated access.
              OT.info "[FromStripePaymentLink] Creating unverified account for #{OT::Utils.obscure_email(checkout_email)}"

              new_cust             = Onetime::Customer.create!(checkout_email)
              new_cust.verified    = false  # Require email verification
              new_cust.verified_by = 'stripe_payment'  # Track payment-initiated account
              new_cust.role        = 'customer'
              new_cust.update_passphrase Onetime::Utils.strand(12)
              new_cust.apply_fields(**update_customer_fields).commit_fields

              # Update organization billing from subscription (extracts planid, etc.)
              update_organization_billing(new_cust)

              # Send verification email so they can complete account setup
              send_verification_email_to(new_cust)

              OT.info "[FromStripePaymentLink] Verification email sent to #{new_cust.obscure_email}"

              # Do NOT authenticate - require email verification first
              # Redirect to signin with message about checking email
              raise OT::Redirect.new('/signin')
            end

          end

          success_data
        end

        def success_data
          { checkout_session_id: checkout_session_id }
        end

        private

        # Update the customer's organization with subscription billing details
        #
        # Fetches the customer's primary organization and updates it with the
        # subscription data, which includes extracting planid from metadata.
        #
        # @param customer [Onetime::Customer] The customer whose organization to update
        # @return [void]
        def update_organization_billing(customer)
          return unless stripe_subscription

          # Find or create default organization via canonical operation
          org = ensure_default_workspace(customer)
          return unless org

          OT.info "[FromStripePaymentLink] Updating organization #{org.objid} billing from subscription #{stripe_subscription.id}"
          org.update_from_stripe_subscription(stripe_subscription)
        rescue Stripe::StripeError, Familia::Problem => ex
          # Log but don't fail the checkout flow - billing can be reconciled later
          billing_logger.error '[FromStripePaymentLink] Error updating organization billing', exception: ex
        end

        # Ensure customer has a default workspace, creating one if needed.
        #
        # Uses the canonical CreateDefaultWorkspace operation which includes
        # federation checks and proper naming conventions.
        #
        # @param customer [Onetime::Customer] The customer needing a workspace
        # @return [Onetime::Organization, nil] The default organization
        def ensure_default_workspace(customer)
          orgs = customer.organization_instances.to_a.reject(&:archived?)

          if customer.default_org_id.to_s.length.positive?
            explicit = orgs.find { |o| o.objid == customer.default_org_id }
            return explicit if explicit
          end

          org = orgs.find(&:is_default) || orgs.first
          return org if org

          # Create via canonical operation (includes federation check)
          OT.info "[FromStripePaymentLink] Creating default workspace for #{customer.obscure_email}"
          result = Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
          result&.dig(:organization)
        end

        # Send verification email to a specific customer
        #
        # Creates a verification secret and sends the welcome email.
        # Similar to base class send_verification_email but takes customer as param.
        #
        # @param customer [Onetime::Customer] The customer to send verification to
        # @return [void]
        def send_verification_email_to(customer)
          msg = format(
            "Thanks for your purchase! Please verify your email to activate your account.\n\n\"%s\"",
            OT::Utils.random_fortune,
          )

          _receipt, secret = Onetime::Receipt.spawn_pair(customer.objid, 24.days, msg)

          secret.verification = true
          secret.custid       = customer.custid
          secret.save

          customer.reset_secret = secret.identifier

          Onetime::Mail::Mailer.deliver(
            :welcome,
            {
              email_address: customer.email,
              secret: secret,
            },
          )
        rescue StandardError => ex
          billing_logger.error '[FromStripePaymentLink] Error sending verification email', exception: ex
        end

        # Preserve existing stripe_customer_id during checkout association
        #
        # When a user already has a stripe_customer_id (from a previous checkout),
        # we keep their existing ID rather than overwriting with the new one.
        # The authoritative billing relationship is now on Organization, but we
        # preserve Customer.stripe_customer_id for data integrity during migration.
        #
        # @param customer [Onetime::Customer] The customer to check
        # @param fields [Hash] The update fields hash (will be modified in place)
        # @return [Hash] The modified fields hash
        def preserve_existing_stripe_customer_id(customer, fields)
          existing_id = customer.stripe_customer_id.to_s
          new_id      = fields[:stripe_customer_id].to_s

          if !existing_id.empty? && existing_id != new_id
            billing_logger.warn '[FromStripePaymentLink] Customer already has stripe_customer_id, keeping existing',
              existing: existing_id,
              new: new_id,
              customer: customer.obscure_email
            fields.delete(:stripe_customer_id)
          end

          fields
        end
      end

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
          # Divergence from the webhook twin, which tries
          # Auth::Operations::CreateDefaultWorkspace first for its pending
          # federated-subscription claim. This path has never called it and
          # that difference is NOT deliberate — see the FEDERATION GAP note on
          # CheckoutCompleted#find_target_organization. Unifying it changes
          # federation behaviour on this surface and is out of scope here.
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
