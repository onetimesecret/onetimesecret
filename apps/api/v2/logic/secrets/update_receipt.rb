# apps/api/v2/logic/secrets/update_receipt.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    # Update Receipt
    #
    # @api Updates a receipt's mutable fields. Currently supports setting
    #   the memo field (up to 500 characters). Only the receipt owner
    #   can perform updates. Returns the updated receipt record.
    class UpdateReceipt < V2::Logic::Base
      SCHEMAS = { response: 'receipt' }.freeze

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
        # V3 inherits this operation; the model owns the conditional write,
        # while success_data retains the safe_dump boundary and wire shape.
        if memo
          raise OT::MissingSecret, "identifier: #{identifier}" unless receipt.update_memo!(memo)

          # Refresh the response projection, not the write precondition. The
          # atomic model operation already protected lifecycle fields and TTL.
          @receipt = Onetime::Receipt.load(identifier)
          raise OT::MissingSecret, "identifier: #{identifier}" if receipt.nil?
        end

        success_data
      end

      def success_data
        { record: receipt.safe_dump }
      end
    end
  end
end
