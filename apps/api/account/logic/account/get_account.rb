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
        success_data
      end

      def success_data
        {
          user_id: cust.extid,
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
