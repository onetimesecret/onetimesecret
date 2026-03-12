# apps/api/v3/logic/incoming/validate_recipient.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/incoming/recipient_resolver'

module V3
  module Logic
    module Incoming
      # Validates that a recipient hash exists in our configured recipients.
      #
      # Domain-aware: uses RecipientResolver to check recipients from
      # either global config (canonical) or per-domain config (custom).
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
          # On custom domains, require the owning org's entitlement
          require_entitlement!('incoming_secrets') if custom_domain?

          # Check if feature is enabled (domain-aware)
          unless resolver.enabled?
            raise_form_error 'Incoming secrets feature is not enabled'
          end

          raise_form_error 'Recipient hash is required' if recipient_hash.empty?
        end

        def process
          # Validate that the hash exists via domain-aware resolver
          @is_valid     = !resolver.lookup(recipient_hash).nil?
          @greenlighted = true
          success_data
        end

        def success_data
          {
            recipient: recipient_hash,
            valid: is_valid,
          }
        end

        private

        def resolver
          @resolver ||= Onetime::Incoming::RecipientResolver.new(
            domain_strategy: domain_strategy,
            display_domain: display_domain,
          )
        end
      end
    end
  end
end
