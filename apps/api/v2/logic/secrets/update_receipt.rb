# apps/api/v2/logic/secrets/update_receipt.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    class UpdateReceipt < V2::Logic::Base
      # Working variables
      attr_reader :identifier, :receipt

      def process_params
        @identifier = sanitize_identifier(params['identifier'])
        @receipt    = Onetime::Receipt.load(identifier)
      end

      def raise_concerns
        require_entitlement!('api_access')
        raise OT::MissingSecret, "identifier: #{identifier}" if receipt.nil?
        raise OT::Unauthorized, 'Not authorized to update this receipt' unless receipt.owner?(cust)
      end

      def process
        # Only allow updating memo field for now
        if params['memo']
          receipt.memo = params['memo']
          receipt.save
        end

        success_data
      end

      def success_data
        { record: receipt.safe_dump }
      end
    end
  end
end
