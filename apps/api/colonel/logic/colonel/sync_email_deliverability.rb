# apps/api/colonel/logic/colonel/sync_email_deliverability.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/sync_provider_feedback'

module ColonelAPI
  module Logic
    module Colonel
      # Trigger an on-demand provider feedback sync (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::SyncProviderFeedback} —
      # the interactive counterpart to `bin/ots email sync-feedback` (the cron
      # path). Neither ingestion transport is a substitute for the other:
      # this lets a colonel resolve "sync has never run" from the browser
      # instead of shelling in, but a cron is still the only way to keep the
      # suppression list current automatically.
      #
      # The request carries NO parameters — it always syncs the active
      # transport (`Mailer.determine_provider`), matching the single-provider
      # deployment model documented on {Onetime::Operations::Email::ProviderStatus}.
      # `LIMIT` bounds the walk so a large provider list can't hang the
      # request; the unbounded full walk stays a cron-only capability.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SyncEmailDeliverability < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailDeliverabilitySync' }.freeze

        # Caps the synchronous provider walk so an interactive request can't
        # hang on a large suppression list. The cron path (`ots email
        # sync-feedback`) has no such cap.
        LIMIT = 500

        attr_reader :result

        def process_params
          # No parameters — always syncs the active transport.
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::Email::SyncProviderFeedback.new(
            actor: cust.extid,
            limit: LIMIT,
          ).call

          success_data
        rescue ArgumentError => ex
          # Active transport has no pull API (e.g. smtp/sendgrid/logger).
          raise_form_error(ex.message)
        rescue StandardError => ex
          # Provider timeout/auth failure — surface it rather than 500ing.
          raise_form_error("Sync failed: #{ex.message}")
        end

        def success_data
          {
            record: {
              provider: result.provider,
              fetched: result.fetched,
              accepted: result.accepted,
              rejected: result.rejected,
            },
            details: {
              errors: result.errors,
            },
          }
        end
      end
    end
  end
end
