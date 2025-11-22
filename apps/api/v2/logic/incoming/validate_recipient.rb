# apps/api/v2/logic/incoming/validate_recipient.rb

require_relative '../base'

module V2::Logic
  module Incoming
    class ValidateRecipient < V2::Logic::Base
      attr_reader :greenlighted, :recipient_hash, :is_valid

      def process_params
        @recipient_hash = params[:recipient].to_s.strip
      end

      def raise_concerns
        # Check if feature is enabled
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        raise_form_error "Recipient hash is required" if recipient_hash.empty?

        limit_action :get_page
      end

      def process
        # Validate that the hash exists in our lookup table
        @is_valid = !OT.lookup_incoming_recipient(recipient_hash).nil?
        @greenlighted = true
      end

      def success_data
        {
          recipient: recipient_hash,
          valid: is_valid
        }
      end
    end
  end
end
