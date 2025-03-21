
require_relative '../../../onetime/refinements/stripe_refinements'

module Onetime::Logic
  module Account

    class GetAccount < OT::Logic::Base
      attr_accessor :plans_enabled
      attr_reader :stripe_subscription, :stripe_customer
      using Onetime::StripeRefinements

      def process_params
        OT.ld "[GetAccount#process_params] params: #{params.inspect}"
        site = OT.conf.fetch(:site, {})
        @plans_enabled = site.dig(:plans, :enabled) || false
      end

      def raise_concerns
        limit_action :show_account
      end

      def process

        if plans_enabled
          @stripe_customer = cust.get_stripe_customer
          @stripe_subscription = cust.get_stripe_subscription

          # Rudimentary normalization to make sure that all Onetime customers
          # that have a stripe customer and subscription record, have the
          # RedisHash fields stripe_customer_id and stripe_subscription_id
          # fields populated. The subscription section on the account screen
          # depends on these ID fields being populated.
          if stripe_customer
            OT.info "Recording stripe customer ID"
            cust.stripe_customer_id = stripe_customer.id
          end

          if stripe_subscription
            OT.info "Recording stripe subscription ID"
            cust.stripe_subscription_id = stripe_subscription.id
          end

          # Just incase we didn't capture the Onetime Secret planid update after
          # a customer subscribes, let's make sure we update it b/c it doesn't
          # feel good to pay for something and still see "Basic Plan" at the
          # top of your account page.
          if stripe_subscription && stripe_subscription.plan
            cust.planid = 'identity' # TOOD: obviously find a better way
          end

          cust.save
        end
      end

      def show_stripe_section?
        plans_enabled && !stripe_customer.nil?
      end

      def safe_stripe_customer_dump
        return nil if stripe_customer.nil?
        {
          id: stripe_customer.id,
          email: stripe_customer.email,
          description: stripe_customer.description,
          balance: stripe_customer.balance,
          created: stripe_customer.created,
          metadata: stripe_customer.metadata
        }
      end

      def safe_stripe_subscription_dump
        return nil if stripe_subscription.nil?
        {
          id: stripe_subscription.id,
          status: stripe_subscription.status,
          current_period_end: stripe_subscription.current_period_end,
          items: stripe_subscription.items,
          plan: {
            id: stripe_subscription.plan.id,
            amount: stripe_subscription.plan.amount,
            currency: stripe_subscription.plan.currency,
            interval: stripe_subscription.plan.interval,
            product: stripe_subscription.plan.product
          }
        }
      end

      def success_data
        ret = {
          custid: cust.custid,
          record: {
            apitoken: cust.apitoken,
            cust: cust.safe_dump,
            stripe_customer: nil,
            stripe_subscriptions: nil
          },
          details: {}
        }

        if show_stripe_section?
          ret[:record][:stripe_customer] = safe_stripe_customer_dump
          subscription = safe_stripe_subscription_dump
          ret[:record][:stripe_subscriptions] = [subscription] if subscription
        end

        ret
      end
    end

  end
end
