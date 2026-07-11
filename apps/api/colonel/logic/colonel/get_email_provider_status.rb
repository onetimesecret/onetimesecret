# apps/api/colonel/logic/colonel/get_email_provider_status.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/provider_status'

module ColonelAPI
  module Logic
    module Colonel
      # Get Email Provider Status (Track B).
      #
      # @api Returns the ACTIVE transport provider's live deliverability status:
      #   SES → enforcement tier + rolling 24h quota (no numeric rate on SESv2);
      #   Lettermint → 30-day sent/delivered/bounce/complaint counts + rates
      #   computed in Ruby. Non-live transports (logger/smtp/sendgrid/disabled)
      #   return capability=false. Requires colonel role.
      #
      # Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
      # Fail-soft: the op never raises — a provider timeout degrades the payload
      # (capability present, available=false + error) instead of 500-ing the page.
      class GetEmailProviderStatus < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailProviderStatus' }.freeze

        attr_reader :result

        def process_params
          # No parameters — reads the active transport, fixed 30-day window.
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::Email::ProviderStatus.new.call
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
