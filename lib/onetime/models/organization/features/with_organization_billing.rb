# lib/onetime/models/organization/features/with_organization_billing.rb

module Onetime
  module Models
    module Features
      # Organization Billing Feature
      #
      # Adds Stripe billing fields and methods to Organization model.
      # Organizations own subscriptions, not customers or teams.
      #
      module WithOrganizationBilling

        Familia::Base.add_feature self, :with_organization_billing

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          base.include InstanceMethods

          # Stripe billing fields
          base.field :stripe_customer_id       # Stripe Customer ID
          base.field :stripe_subscription_id   # Active Stripe Subscription ID
          base.field :planid                   # Plan identifier (e.g., 'single_team_monthly')
          base.field :billing_email            # Billing contact email
          base.field :subscription_status      # active, past_due, canceled, etc.
          base.field :subscription_period_end  # Unix timestamp when current period ends
          base.field :stripe_checkout_email    # Not necessarily the same as billing_email

          # Add indexes. e.g. unique_index :extid, :extid_index, within: Onetime::Organization
          base.unique_index :stripe_customer_id, :stripe_customer_id_index
          base.unique_index :stripe_subscription_id, :stripe_subscription_id_index
          base.unique_index :stripe_checkout_email, :stripe_checkout_email_index
        end

        module InstanceMethods

          # Retrieve Stripe customer object
          #
          # @return [Stripe::Customer, nil] Stripe customer or nil if not found
          def stripe_customer
            return nil if stripe_customer_id.to_s.empty?

            @stripe_customer ||= Stripe::Customer.retrieve(stripe_customer_id)
          rescue Stripe::StripeError => ex
            OT.le "[Organization.stripe_customer] Error: #{ex.message}"
            nil
          end

          # Retrieve Stripe subscription object
          #
          # @return [Stripe::Subscription, nil] Stripe subscription or nil if not found
          def stripe_subscription
            return nil if stripe_subscription_id.to_s.empty?

            @stripe_subscription ||= Stripe::Subscription.retrieve(stripe_subscription_id)
          rescue Stripe::StripeError => ex
            OT.le "[Organization.stripe_subscription] Error: #{ex.message}"
            nil
          end

          # Check if organization has an active subscription
          #
          # @return [Boolean] True if subscription status is 'active' or 'trialing'
          def active_subscription?
            %w[active trialing].include?(subscription_status.to_s)
          end

          # Check if subscription is past due
          #
          # @return [Boolean] True if subscription status is 'past_due'
          def past_due?
            subscription_status.to_s == 'past_due'
          end

          # Check if subscription is canceled
          #
          # @return [Boolean] True if subscription status is 'canceled'
          def canceled?
            subscription_status.to_s == 'canceled'
          end

          # Update billing fields from Stripe subscription
          #
          # @param subscription [Stripe::Subscription] Stripe subscription object
          # @return [Boolean] True if saved successfully
          def update_from_stripe_subscription(subscription)
            self.stripe_subscription_id = subscription.id
            self.stripe_customer_id = subscription.customer
            self.subscription_status = subscription.status
            self.subscription_period_end = subscription.current_period_end.to_s

            # Extract plan ID from subscription metadata or price metadata
            if subscription.metadata && subscription.metadata['plan_id']
              self.planid = subscription.metadata['plan_id']
            elsif subscription.items.data.first&.price&.metadata&.[]('plan_id')
              self.planid = subscription.items.data.first.price.metadata['plan_id']
            end

            save
          end

          # Clear billing fields (on subscription cancellation)
          #
          # @return [Boolean] True if saved successfully
          def clear_billing_fields
            self.stripe_subscription_id = nil
            self.subscription_status = 'canceled'
            save
          end

          # Robust Stripe customer retrieval with fallbacks
          #
          # Tries in order:
          # 1. stripe_customer_id (if set) - uses stripe_customer method
          # 2. billing_email lookup
          # 3. stripe_checkout_email lookup
          # 4. contact_email lookup
          #
          # @return [Stripe::Customer, nil] Stripe customer or nil if not found
          def get_stripe_customer
            return stripe_customer if stripe_customer_id.to_s.present?

            get_stripe_customer_by_email
          rescue Stripe::StripeError => ex
            OT.le "[Organization.get_stripe_customer] Error: #{ex.message}"
            nil
          end

          # Find Stripe customer by email (tries multiple email fields)
          #
          # Attempts to find Stripe customer using organization email fields in priority order:
          # 1. billing_email (primary billing contact)
          # 2. stripe_checkout_email (email used during Stripe checkout)
          # 3. contact_email (general organization contact)
          #
          # @return [Stripe::Customer, nil] Stripe customer or nil if not found
          def get_stripe_customer_by_email
            email_to_try = billing_email.to_s.presence ||
                           stripe_checkout_email.to_s.presence ||
                           contact_email.to_s.presence

            return nil if email_to_try.blank?

            OT.info "[Organization.get_stripe_customer_by_email] Searching for: #{email_to_try}"
            customers = Stripe::Customer.list(email: email_to_try, limit: 1)

            if customers.data.empty?
              OT.info "[Organization.get_stripe_customer_by_email] No customer found: #{email_to_try}"
              nil
            else
              @stripe_customer = customers.data.first
              OT.info "[Organization.get_stripe_customer_by_email] Found: #{@stripe_customer.id}"
              @stripe_customer
            end
          rescue Stripe::StripeError => ex
            OT.le "[Organization.get_stripe_customer_by_email] Error: #{ex.message}"
            nil
          end

          # Robust subscription retrieval with fallback to listing
          #
          # Tries in order:
          # 1. stripe_subscription_id (if set) - uses stripe_subscription method
          # 2. List active subscriptions for customer and take first
          #
          # Note: Organizations should only have ONE subscription. If multiple subscriptions
          # exist, this returns the first active one found.
          #
          # @return [Stripe::Subscription, nil] Stripe subscription or nil if not found
          def get_stripe_subscription
            return stripe_subscription if stripe_subscription_id.to_s.present?

            # Fallback: Get customer's subscriptions and take first active one
            customer = get_stripe_customer
            return nil unless customer

            OT.info "[Organization.get_stripe_subscription] Listing subscriptions for customer: #{customer.id}"
            subscriptions = Stripe::Subscription.list(
              customer: customer.id,
              status: 'active',
              limit: 1
            )

            if subscriptions.data.empty?
              OT.info "[Organization.get_stripe_subscription] No active subscriptions found"
              nil
            else
              subscription = subscriptions.data.first
              OT.info "[Organization.get_stripe_subscription] Found subscription: #{subscription.id}"
              subscription
            end
          rescue Stripe::StripeError => ex
            OT.le "[Organization.get_stripe_subscription] Error: #{ex.message}"
            nil
          end

        end

      end

    end
  end
end
