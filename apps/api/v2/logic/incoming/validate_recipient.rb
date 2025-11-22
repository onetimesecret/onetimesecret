# apps/api/v2/logic/incoming/validate_recipient.rb

require_relative '../base'

module V2::Logic
  module Incoming
    class ValidateRecipient < V2::Logic::Base
      attr_reader :greenlighted, :recipient_email, :is_valid

      def process_params
        @recipient_email = params[:recipient].to_s.strip
      end

      def raise_concerns
        # Check if feature is enabled
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        raise_form_error "Recipient email is required" if recipient_email.empty?

        limit_action :get_page
      end

      def process
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        allowed_recipients = (incoming_config[:recipients] || []).map { |r| r[:email] }

        @is_valid = allowed_recipients.include?(recipient_email)
        @greenlighted = true
      end

      def success_data
        {
          recipient: recipient_email,
          valid: is_valid
        }
      end
    end
  end
end
