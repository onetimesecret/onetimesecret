# apps/api/colonel/logic/colonel/lookup_email_recipient.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/models/email_suppression'
require 'onetime/operations/email/recipient_lookup'

module ColonelAPI
  module Logic
    module Colonel
      # Look up one recipient address across the local suppression store AND the
      # live active-transport provider (Track B, item 10).
      #
      # @api Given ?address=, returns BOTH the local suppression status (always
      #   present — the authority) and the live provider suppression status
      #   (fail-soft). Requires colonel role.
      #
      # PII live-read rationale (mandatory): this returns the plaintext recipient
      # address and its live provider suppression status. This is EXEMPT from the
      # epic's at-rest address-hashing posture BECAUSE it is a live admin read,
      # colonel-only, never persisted — do not flag it as a hashing regression.
      #
      # Read-only: nothing mutates, so nothing is audited (CONTRACT 4).
      class LookupEmailRecipient < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailRecipientLookup' }.freeze

        attr_reader :address, :result

        def process_params
          # Item-10 normalization: key via EmailSuppression.normalize
          # (strip.downcase) for BOTH the local read and the provider lookup.
          # FORBIDDEN: OT::Utils.normalize_email / EmailHash (NFC +
          # downcase(:fold)) — it would not match the stored suppression keys and
          # every lookup would silently miss.
          @address = Onetime::EmailSuppression.normalize(params['address'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('address required', field: :address) if address.empty?
        end

        def process
          @result = Onetime::Operations::Email::RecipientLookup.new(address: address).call
          success_data
        end

        def success_data
          {
            record: {},
            details: result.to_h,
          }
        end
      end
    end
  end
end
