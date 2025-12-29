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
          @checkout_session = Stripe::Checkout::Session.retrieve(checkout_session_id)
          raise_form_error 'Invalid Stripe checkout session' unless checkout_session

          # Fetch the full subscription to extract plan metadata
          if checkout_session.subscription
            @stripe_subscription = Stripe::Subscription.retrieve(checkout_session.subscription)
          end

          @checkout_email         = checkout_session.customer_details.email
          @update_customer_fields = {
            stripe_checkout_email: checkout_email,
            stripe_subscription_id: checkout_session.subscription,
            stripe_customer_id: checkout_session.customer,
          }
        end

        def process
          if @sess['authenticated'] == true
            # If the user is already authenticated, we can associate the checkout
            # session with their account.

            if checkout_email.eql?(cust.email)
              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with authenticated user #{cust.email}"

            else
              # Log the discrepancy
              OT.le "[FromStripePaymentLink] Email mismatch: #{checkout_email} !== authenticated user email #{cust.email}"
            end

            # Proceed with associating the checkout session with the
            # authenticated account.

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

              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with existing user #{cust.email}"

              cust.apply_fields(**update_customer_fields).commit_fields

              # Update organization billing from subscription (extracts planid, etc.)
              update_organization_billing(cust)

              raise OT::Redirect.new('/signin')
            else
              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with new user #{checkout_email}"

              cust          = Onetime::Customer.create!(checkout_email)
              cust.verified = 'true'
              cust.role     = 'customer'
              cust.update_passphrase Onetime::Utils.strand(12)
              cust.apply_fields(**update_customer_fields).commit_fields

              # Create a completely new session, new id, new everything (incl
              # cookie which the controllor will implicitly do above when it
              # resends the cookie with the new session id).
              OT.info "[FromStripePaymentLink:login-success] #{sess} #{cust.obscure_email} #{cust.role}"

              # Set session authentication data
              sess['external_id']      = cust.extid
              sess['authenticated']    = true
              sess['authenticated_at'] = Familia.now.to_i

              # Update organization billing from subscription (extracts planid, etc.)
              update_organization_billing(cust)

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

          # Find default organization (matches CheckoutCompleted pattern)
          orgs = customer.organization_instances.to_a
          org = orgs.find { |o| o.is_default }
          unless org
            OT.lw "[FromStripePaymentLink] No default organization found for customer #{customer.obscure_email}"
            return
          end

          OT.info "[FromStripePaymentLink] Updating organization #{org.objid} billing from subscription #{stripe_subscription.id}"
          org.update_from_stripe_subscription(stripe_subscription)
        rescue StandardError => ex
          # Log but don't fail the checkout flow - billing can be reconciled later
          OT.le "[FromStripePaymentLink] Error updating organization billing: #{ex.message}"
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
          })
          raise_form_error 'Invalid checkout session' unless checkout_session

          @subscription = checkout_session.subscription
          # Note: subscription may be nil for one-time payments
        end

        def process
          return success_data unless subscription

          metadata = subscription.metadata
          custid   = metadata['custid']
          plan_id  = metadata['plan_id']

          OT.info '[ProcessCheckoutSession] Processing checkout', {
            session_id: session_id,
            custid: custid,
            plan_id: plan_id,
            subscription_id: subscription.id,
          }

          # Find or create default organization for the customer
          org = find_or_create_default_organization(cust)

          # Update organization with subscription details (extracts planid, etc.)
          org.update_from_stripe_subscription(subscription)

          OT.info '[ProcessCheckoutSession] Organization subscription activated', {
            orgid: org.objid,
            subscription_id: subscription.id,
            plan_id: plan_id,
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
          org = orgs.find { |o| o.is_default }

          return org if org

          # Create default organization if none exists
          OT.info "[ProcessCheckoutSession] Creating default organization for #{customer.obscure_email}"
          Onetime::Organization.create(customer)
        end
      end
    end
  end
end
