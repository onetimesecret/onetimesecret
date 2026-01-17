# apps/api/v2/logic/secrets/update_receipt.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    class UpdateReceipt < V2::Logic::Base
      # Maximum length for memo field (matches feedback message limit)
      MEMO_MAX_LENGTH = 500

      # Working variables
      attr_reader :identifier, :receipt, :memo

      def process_params
        @identifier = sanitize_identifier(params['identifier'])
        @memo       = sanitize_plain_text(params['memo'], max_length: MEMO_MAX_LENGTH) if params['memo']
        @receipt    = Onetime::Receipt.load(identifier)
      end

      def raise_concerns
        require_entitlement!('api_access')
        raise OT::MissingSecret, "identifier: #{identifier}" if receipt.nil?
        raise OT::Unauthorized, 'Not authorized to update this receipt' unless receipt.owner?(cust)
      end

      def process
        # Only allow updating memo field for now
        if memo
          receipt.memo = memo
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
