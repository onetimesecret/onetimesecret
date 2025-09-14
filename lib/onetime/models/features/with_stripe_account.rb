# lib/onetime/models/features/with_stripe_account.rb

module V2
  module Models
    module Features
      #
      #
      module WithStripeAccount

        Familia::Base.add_feature self, :with_stripe_account

        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"

          base.include InstanceMethods

          base.field :stripe_customer_id
          base.field :stripe_subscription_id
          base.field :stripe_checkout_email
        end

        module InstanceMethods

          def get_stripe_customer
            get_stripe_customer_by_id || get_stripe_customer_by_email
          rescue Stripe::StripeError => ex
            OT.le "[Customer.get_stripe_customer] Error: #{ex.message}: #{ex.backtrace}"
            nil
          end

          def get_stripe_subscription
            get_stripe_subscription_by_id || get_stripe_subscriptions&.first
          end

          def get_stripe_customer_by_id(customer_id = nil)
            customer_id ||= stripe_customer_id
            return if customer_id.to_s.empty?

            OT.info "[Customer.get_stripe_customer_by_id] Fetching customer: #{customer_id} #{custid}"
            @stripe_customer = Stripe::Customer.retrieve(customer_id)
          rescue Stripe::StripeError => ex
            OT.le "[Customer.get_stripe_customer_by_id] Error: #{ex.message}"
            nil
          end

          def get_stripe_customer_by_email
            customers = Stripe::Customer.list(email: email, limit: 1)

            if customers.data.empty?
              OT.info "[Customer.get_stripe_customer_by_email] No customer found with email: #{email}"

            else
              @stripe_customer = customers.data.first
              OT.info "[Customer.get_stripe_customer_by_email] Customer found: #{@stripe_customer.id}"
            end

            @stripe_customer
          rescue Stripe::StripeError => ex
            OT.le "[Customer.get_stripe_customer_by_email] Error: #{ex.message}"
            nil
          end

          def get_stripe_subscription_by_id(subscription_id = nil)
            subscription_id ||= stripe_subscription_id
            return if subscription_id.to_s.empty?

            OT.info "[Customer.get_stripe_subscription_by_id] Fetching subscription: #{subscription_id} #{custid}"
            @stripe_subscription = Stripe::Subscription.retrieve(subscription_id)
          rescue Stripe::StripeError => ex
            OT.le "[Customer.get_stripe_subscription_by_id] Error: #{ex.message}"
            nil
          end

          def get_stripe_subscriptions(stripe_customer = nil)
            stripe_customer ||= @stripe_customer
            subscriptions     = []
            return subscriptions unless stripe_customer

            begin
              subscriptions = Stripe::Subscription.list(customer: stripe_customer.id, limit: 1)
            rescue Stripe::StripeError => ex
              OT.le "Error: #{ex.message}"
            else
              if subscriptions.data.empty?
                OT.info "No subscriptions found for customer: #{stripe_customer.id}"
              else
                OT.info "Found #{subscriptions.data.length} subscriptions"
                subscriptions = subscriptions.data
              end
            end

            subscriptions
          end

        end

      end

    end
  end
end
