# apps/api/colonel/logic/colonel/get_email_config.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/config_summary'

module ColonelAPI
  module Logic
    module Colonel
      # Get Mailer Configuration (Colonel).
      #
      # @api Returns the standing email-delivery configuration: the active
      #   transport provider, whether it was auto-detected, the from
      #   address/name, a MASKED provider_config (host/port/domain/tls/region +
      #   a has_credentials boolean — NEVER secrets), and the sender-domain
      #   provisioning provider (CUSTOM_MAIL_PROVIDER → determine_sender_provider)
      #   with a `sender_differs` flag. Requires colonel role.
      #
      # Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
      # Thin adapter over {Onetime::Operations::Email::ConfigSummary} — the same
      # summary the `bin/ots email config` CLI renders, so the two never drift.
      #
      # Security invariant (items 1 + 11): the summary carries ONLY booleans
      # (has_credentials) and non-secret config. The raw Onetime.conf['emailer']
      # (which carries user/pass) is NEVER returned.
      class GetEmailConfig < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailConfig' }.freeze

        attr_reader :summary

        def process_params
          # No parameters — the config is global.
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @summary = Onetime::Operations::Email::ConfigSummary.build

          success_data
        end

        private

        def success_data
          {
            record: {},
            details: summary,
          }
        end
      end
    end
  end
end
