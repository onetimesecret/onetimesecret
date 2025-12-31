# apps/web/billing/logic/welcome.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'

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
        attr_reader :checkout_session_id, :checkout_session, :checkout_email,
          :update_customer_fields, :stripe_subscription

        def process_params
          @checkout_session_id = params[:checkout]
        end

        def raise_concerns
          raise_form_error 'No Stripe checkout_session_id' unless checkout_session_id

          # Use expand to fetch subscription in a single API call
          @checkout_session = Stripe::Checkout::Session.retrieve({
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
              OT.le "[FromStripePaymentLink] Email mismatch: checkout email differs from authenticated user #{cust.obscure_email}"
              raise_form_error 'Please log out first to complete checkout with a different email address'
            end

            OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with authenticated user #{cust.obscure_email}"

            # TODO: Handle case where the user is already a Stripe customer
            cust.apply_fields(**update_customer_fields).commit_fields

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

              cust.apply_fields(**update_customer_fields).commit_fields

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

          # Find or create default organization
          orgs = customer.organization_instances.to_a
          org  = orgs.find(&:is_default)

          unless org
            OT.info "[FromStripePaymentLink] No default organization found, creating one for customer #{customer.obscure_email}"
            org            = Onetime::Organization.create!(
              "#{customer.email}'s Workspace",
              customer,
              customer.email,
            )
            org.is_default = true
            org.save
          end

          OT.info "[FromStripePaymentLink] Updating organization #{org.objid} billing from subscription #{stripe_subscription.id}"
          org.update_from_stripe_subscription(stripe_subscription)
        rescue Stripe::StripeError, Familia::Problem => ex
          # Log but don't fail the checkout flow - billing can be reconciled later
          OT.le "[FromStripePaymentLink] Error updating organization billing: #{ex.message}"
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

          _metadata, secret = Onetime::Metadata.spawn_pair(customer.objid, 24.days, msg)

          secret.verification = true
          secret.custid       = customer.custid
          secret.save

          customer.reset_secret = secret.identifier

          Onetime::Mail::Mailer.deliver(:welcome, {
            email_address: customer.email,
            secret: secret,
          }
          )
        rescue StandardError => ex
          OT.le "[FromStripePaymentLink] Error sending verification email: #{ex.message}"
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
        attr_reader :session_id, :checkout_session, :subscription

        def process_params
          @session_id = params[:session_id]
        end

        def raise_concerns
          raise_form_error 'No session_id provided' unless session_id

          @checkout_session = Stripe::Checkout::Session.retrieve({
            id: session_id,
            expand: %w[subscription customer],
          },
                                                                )
          raise_form_error 'Invalid checkout session' unless checkout_session

          @subscription = checkout_session.subscription
          # NOTE: subscription may be nil for one-time payments
        end

        def process
          return success_data unless subscription

          metadata        = subscription.metadata
          # Support both new (customer_extid) and legacy (custid) metadata formats
          customer_extid  = metadata['customer_extid'] || metadata['custid']
          plan_id         = metadata['plan_id']

          OT.info '[ProcessCheckoutSession] Processing checkout', {
            session_id: session_id,
            customer_extid: customer_extid,
            plan_id: plan_id,
            subscription_id: subscription.id,
          }

          # Load the actual customer from metadata (session may be anonymous after Stripe redirect)
          # The customer_extid was embedded in subscription metadata when checkout was created
          customer = Onetime::Customer.find_by_extid(customer_extid)
          unless customer
            OT.le "[ProcessCheckoutSession] Customer not found: #{customer_extid}"
            raise_form_error 'Customer not found'
          end

          # Find or create default organization for the customer
          org = find_or_create_default_organization(customer)

          # Update organization with subscription details (extracts planid, etc.)
          org.update_from_stripe_subscription(subscription)

          OT.info '[ProcessCheckoutSession] Organization subscription activated', {
            orgid: org.objid,
            subscription_id: subscription.id,
            plan_id: org.planid,  # Use actual planid set by update_from_stripe_subscription
          }

          success_data
        end

        def success_data
          { session_id: session_id, success: true }
        end

        private

        # Find existing default organization or create one
        #
        # @param customer [Onetime::Customer] The customer
        # @return [Onetime::Organization] The default organization
        def find_or_create_default_organization(customer)
          orgs = customer.organization_instances.to_a
          org  = orgs.find { |o| o.is_default }

          return org if org

          # Create default organization if none exists
          OT.info "[ProcessCheckoutSession] Creating default organization for #{customer.obscure_email}"
          Onetime::Organization.create!(
            "#{customer.email}'s Workspace",
            customer,
            customer.email,
          )
        end
      end
    end
  end
end
