# apps/api/account/logic/account/get_account.rb
#
# frozen_string_literal: true

require 'onetime/refinements/stripe_refinements'

module AccountAPI::Logic
  module Account
    class GetAccount < AccountAPI::Logic::Base
      attr_accessor :billing_enabled
      attr_reader :stripe_subscription, :stripe_customer

      using Onetime::StripeRefinements

      def process_params
        OT.ld "[GetAccount#process_params] params: #{params.inspect}"
        @billing_enabled = OT.billing_config.enabled?
      end

      def raise_concerns; end

      def process
        return unless billing_enabled

        # @stripe_customer     = cust.get_stripe_customer
        # @stripe_subscription = cust.get_stripe_subscription

        # # Rudimentary normalization to make sure that all Onetime customers
        # # that have a stripe customer and subscription record, have the
        # # RedisHash fields stripe_customer_id and stripe_subscription_id
        # # fields populated. The subscription section on the account screen
        # # depends on these ID fields being populated.
        # if stripe_customer
        #   OT.info 'Recording stripe customer ID'
        #   cust.stripe_customer_id = stripe_customer.id
        # end

        # if stripe_subscription
        #   OT.info 'Recording stripe subscription ID'
        #   cust.stripe_subscription_id = stripe_subscription.id
        # end

        # cust.save

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: {
            apitoken: cust.apitoken,
            cust: cust.safe_dump,
          },
          details: {},
        }
      end
    end
  end
end
