# apps/api/v2/controllers/incoming.rb

require_relative 'base'
require_relative '../logic/incoming'

module V2
  module Controllers
    class Incoming
      include V2::Controllers::Base

      @check_utf8 = true
      @check_uri_encoding = true

      def get_config
        retrieve_records(V2::Logic::Incoming::GetConfig, allow_anonymous: true)
      end

      def create_secret
        process_action(
          V2::Logic::Incoming::CreateIncomingSecret,
          "Incoming secret created successfully.",
          "Incoming secret could not be created.",
          allow_anonymous: true,
        )
      end

      def validate_recipient
        retrieve_records(V2::Logic::Incoming::ValidateRecipient, allow_anonymous: true)
      end

      # Guest Routes - Anonymous API access for incoming secrets
      # Uses publically block (minimal session, no auth required)

      def guest_get_config
        publically do
          require_guest_routes!(:incoming)
          retrieve_guest_records(V2::Logic::Incoming::GetConfig)
        end
      end

      def guest_create_secret
        publically do
          require_guest_routes!(:incoming)
          process_guest_action(V2::Logic::Incoming::CreateIncomingSecret)
        end
      end

      def guest_validate_recipient
        publically do
          require_guest_routes!(:incoming)
          retrieve_guest_records(V2::Logic::Incoming::ValidateRecipient)
        end
      end

      private

      def process_guest_action(logic_class)
        @cust ||= V2::Customer.anonymous
        logic = logic_class.new(sess, cust, req.params, locale)
        logic.domain_strategy = req.env['onetime.domain_strategy']
        logic.display_domain = req.env['onetime.display_domain']
        logic.raise_concerns
        logic.process

        if logic.greenlighted
          json_success(custid: cust.custid, **logic.success_data)
        else
          error_response("Action could not be completed", shrimp: sess.add_shrimp)
        end
      end

      def retrieve_guest_records(logic_class)
        @cust ||= V2::Customer.anonymous
        logic = logic_class.new(sess, cust, req.params, locale)
        logic.domain_strategy = req.env['onetime.domain_strategy']
        logic.display_domain = req.env['onetime.display_domain']
        logic.raise_concerns
        logic.process
        json success: true, **logic.success_data
      end
    end
  end
end
