# apps/api/colonel/logic/colonel/list_pending_federated_subscriptions.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/billing/webhook_visibility'

module ColonelAPI
  module Logic
    module Colonel
      # Bounded local view of federated subscriptions awaiting a verified claim.
      #
      # The projection deliberately omits email_hash and every customer field.
      # Legacy records surface source_webhook.state = "no_correlation"; rows
      # whose retained source webhook has expired surface state = "expired".
      class ListPendingFederatedSubscriptions < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelPendingFederatedSubscriptions' }.freeze

        attr_reader :page, :per_page, :result

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || Onetime::Operations::Billing::WebhookVisibility::DEFAULT_PER_PAGE).to_i
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = visibility.list_pending_federated_subscriptions(page: page, per_page: per_page)
          success_data
        end

        def success_data
          {
            record: {},
            details: {
              subscriptions: result.rows,
              pagination: {
                page: result.page,
                per_page: result.per_page,
                total_count: result.total_count,
                total_pages: result.total_pages,
                capped: result.capped,
              },
            },
          }
        end

        private

        def visibility
          @visibility ||= Onetime::Operations::Billing::WebhookVisibility.new
        end
      end
    end
  end
end
