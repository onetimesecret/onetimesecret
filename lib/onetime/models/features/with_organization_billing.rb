# lib/onetime/models/features/with_organization_billing.rb

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

        end

      end

    end
  end
end
