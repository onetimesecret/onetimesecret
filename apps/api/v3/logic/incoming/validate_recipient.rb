# apps/api/v3/logic/incoming/validate_recipient.rb
#
# frozen_string_literal: true

require_relative '../base'

module V3
  module Logic
    module Incoming
      # Validates that a recipient hash exists in our configured recipients.
      #
      # Used by the frontend to verify a recipient selection before
      # submitting the full secret creation request.
      #
      # @example Request
      #   POST /api/v3/incoming/validate
      #   { recipient: "abc123..." }
      #
      # @example Response
      #   { recipient: "abc123...", valid: true }
      #
      class ValidateRecipient < V3::Logic::Base
        attr_reader :greenlighted, :recipient_hash, :is_valid

        def process_params
          @recipient_hash = params['recipient'].to_s.strip
        end

        def raise_concerns
          # Check if feature is enabled
          incoming_config = OT.conf.dig('features', 'incoming') || {}
          unless incoming_config['enabled']
            raise_form_error 'Incoming secrets feature is not enabled'
          end

          raise_form_error 'Recipient hash is required' if recipient_hash.empty?
        end

        def process
          # Validate that the hash exists in our lookup table
          @is_valid = !OT.lookup_incoming_recipient(recipient_hash).nil?
          @greenlighted = true
          success_data
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
end
