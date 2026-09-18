# apps/api/colonel/logic/colonel/list_stripe_webhook_events.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/billing/webhook_visibility'

module ColonelAPI
  module Logic
    module Colonel
      # Bounded local view of retained Stripe webhook processing records.
      #
      # This is intentionally not a Stripe API reader and does not offer replay.
      # Rows are an explicit allowlist: they never expose the saved event payload,
      # affected Stripe object id, request id, customer identifiers, or errors.
      class ListStripeWebhookEvents < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelWebhookEvents' }.freeze

        attr_reader :page, :per_page, :result

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || Onetime::Operations::Billing::WebhookVisibility::DEFAULT_PER_PAGE).to_i
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = visibility.list_webhook_events(page: page, per_page: per_page)
          success_data
        end

        def success_data
          {
            record: {},
            details: {
              events: result.rows,
              pagination: pagination,
              capped: result.capped,
              stale_count: result.stale_count,
            },
          }
        end

        private

        def visibility
          @visibility ||= Onetime::Operations::Billing::WebhookVisibility.new
        end

        def pagination
          {
            page: result.page,
            per_page: result.per_page,
            total_count: result.total_count,
            total_pages: result.total_pages,
            # The count is a lower bound when the bounded Redis walk stopped.
            capped: result.capped,
            # Index entries on this page whose object no longer loads; they are
            # pruned lazily, so a page can be short of `per_page` even mid-list.
            stale_count: result.stale_count,
          }
        end
      end
    end
  end
end
